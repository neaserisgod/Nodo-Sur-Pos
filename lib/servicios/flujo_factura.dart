// El flujo de "Leer una factura" sin pantalla (El dueño, 2026-10-07: "que las funciones del sistema desktop estén disponibles para el
// apk, reutilizando la lógica"). Lo usan el diálogo de la PC (`ui/proveedores/dialogo_leer_factura.dart`) y la pantalla del celular
// (`companion/pantalla_cargar_factura.dart`): las dos solo dibujan y le avisan a este flujo lo que el dueño toca.
//
// Trabaja contra la base del equipo en el que corre. En el celular es su base propia, que la sincronización lleva a la PC (v61: la
// cuenta corriente y las facturas viajan): así carga facturas aunque la PC esté apagada.
//
// Qué hace cada paso — leer, vincular, bultos, aplicar, deshacer — y por qué, está en `docs/PLAN-FACTURAS.md` y `DECISIONES.md`; acá
// solo se orquesta lo que ya vive en `domain/` (cuentas, vínculos, bultos) y en `data/` (aprender, aplicar, deshacer).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/repositorio_facturas_compra.dart';
import '../data/repositorio_productos.dart' show listarProveedores, precioTrasCambioDeCosto;
import '../data/repositorio_vinculos_factura.dart';
import '../domain/aplicar_factura.dart';
import '../domain/dinero.dart';
import '../domain/factura_compra.dart';
import '../domain/lectura_factura.dart';
import '../domain/unidades_bulto.dart';
import '../domain/vinculo_factura.dart';
import 'gemini.dart';
import 'lector_facturas.dart';
import 'nombre_producto_ia.dart';
import 'preparar_imagen.dart';
import 'vinculador_ia.dart';

/// Todo lo de una factura leída: el proveedor, la propuesta de vínculos y lo que el dueño fue eligiendo.
class EstadoFactura {
  EstadoFactura(this.n);

  final FacturaNormalizada n;
  Proveedor? proveedor;

  /// Los proveedores que tienen el CUIT de la factura: pueden ser varios ("X" y "X cigarrillos").
  List<Proveedor> delCuit = const [];
  List<PropuestaDeVinculo> propuestas = const [];

  /// El producto elegido y las unidades por cantidad de cada línea (arrancan con lo propuesto).
  List<int?> producto = const [];
  List<int> multiplicador = const [];

  /// Por qué se propuso ese "× unid." en las líneas donde no es lo aprendido (bulto o unidades): se le muestra al dueño para que confirme.
  Map<int, String> motivoUnidades = {};

  /// Los productos que se ofrecen para elegir en cada línea, por nombre: los del proveedor, las alternativas y lo elegido.
  List<ProductoCandidato> candidatos = const [];

  /// Las líneas que no son del local: entran en la deuda, no en el stock ni el costo.
  List<bool> noVa = const [];

  /// Línea → aviso de que con el costo nuevo el producto queda perdiendo plata.
  Map<int, String> avisosPrecio = {};
  bool sumarStock = true;
  bool aplicando = false;
  int? facturaAplicadaId;
  String? resumenAplicada;
  String? errorAplicar;

  /// Sube cada vez que se vuelve a proponer: obliga a los campos a tomar los valores nuevos.
  int version = 0;
  bool consultandoIa = false;
  String? avisoIa;
  String? avisoAprendido;

  int get vinculadas => producto.where((p) => p != null).length;

  /// La factura no cierra con su total impreso: antes de aplicar se le pregunta al dueño si sigue igual.
  bool get hayQueConfirmar => n.control != null && !n.cierra;
}

class FlujoFactura extends ChangeNotifier {
  /// [clienteIa] es solo para tests.
  FlujoFactura({required this.db, this.clienteIa, List<AdjuntoGemini> adjuntosIniciales = const []})
      : adjuntos = [...adjuntosIniciales],
        nombres = [for (var i = 0; i < adjuntosIniciales.length; i++) 'archivo ${i + 1}'];

  final AppDatabase db;
  final http.Client? clienteIa;

  final List<AdjuntoGemini> adjuntos;
  final List<String> nombres;
  bool leyendo = false;
  String? error;
  ResultadoDeLectura? resultado;
  List<EstadoFactura> facturas = const [];
  List<ProductoCandidato> catalogo = const [];
  List<Proveedor> proveedores = const [];

  bool _cerrado = false;

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  /// Se puede tocar "Leer con IA".
  bool get puedeLeer => !leyendo && adjuntos.isNotEmpty && ClaveGemini.configurada;

  /// Prepara los archivos elegidos (los PDF van tal cual, las fotos se achican) y reemplaza los anteriores. Uno que no es ni foto ni PDF
  /// se saltea con un aviso en [error].
  Future<void> elegirArchivos(List<({String nombre, Uint8List bytes})> archivos) async {
    if (archivos.isEmpty) return;
    error = null;
    leyendo = true;
    _avisar();
    final nuevos = <AdjuntoGemini>[];
    final nombresNuevos = <String>[];
    for (final f in archivos) {
      final adjunto = await prepararArchivoDeFactura(f.nombre, f.bytes);
      if (adjunto == null) {
        error = 'No pude abrir "${f.nombre}": tiene que ser una foto o un PDF.';
        continue;
      }
      nuevos.add(adjunto);
      nombresNuevos.add('${f.nombre} (${(adjunto.bytes.length / 1024).round()} KB)');
    }
    adjuntos
      ..clear()
      ..addAll(nuevos);
    nombres
      ..clear()
      ..addAll(nombresNuevos);
    resultado = null;
    facturas = const [];
    leyendo = false;
    _avisar();
  }

  /// Suma una foto más (la cámara del celular saca de a una: una factura larga son varias fotos).
  Future<void> agregarArchivo(String nombre, Uint8List bytes) async {
    leyendo = true;
    error = null;
    _avisar();
    final adjunto = await prepararArchivoDeFactura(nombre, bytes);
    if (adjunto == null) {
      error = 'No pude abrir "$nombre": tiene que ser una foto o un PDF.';
    } else {
      adjuntos.add(adjunto);
      nombres.add('$nombre (${(adjunto.bytes.length / 1024).round()} KB)');
      resultado = null;
      facturas = const [];
    }
    leyendo = false;
    _avisar();
  }

  void quitarArchivo(int i) {
    adjuntos.removeAt(i);
    nombres.removeAt(i);
    resultado = null;
    facturas = const [];
    _avisar();
  }

  /// Manda los archivos a la IA y arma cada factura leída: reconoce el proveedor por el CUIT y propone los vínculos.
  Future<void> leer() async {
    leyendo = true;
    error = null;
    resultado = null;
    facturas = const [];
    _avisar();
    try {
      final r = await leerFacturasConGemini(adjuntos, client: clienteIa);
      catalogo = await catalogoParaVincular(db);
      proveedores = [for (final p in await listarProveedores(db)) if (p.activo) p];
      final estados = [for (final f in r.lectura.facturas) EstadoFactura(normalizarFactura(f))];
      if (_cerrado) return;
      resultado = r;
      facturas = estados;
      leyendo = false;
      _avisar();
      for (final e in estados) {
        e.delCuit = [for (final p in await proveedoresPorCuit(db, e.n.leida.proveedorCuit)) if (p.activo) p];
        final ids = [for (final p in e.delCuit) p.id];
        // Con varios proveedores para el mismo CUIT decide lo que trae la factura; si no se puede decidir, se pregunta.
        final elegido = elegirProveedorDeFactura(
          candidatos: ids,
          lineas: [for (final l in e.n.lineas) LineaAVincular(codigo: l.codigo, descripcion: l.descripcion)],
          catalogo: catalogo,
          vinculosPorProveedor: await vinculosDeVarios(db, ids),
        );
        e.proveedor = elegido == null ? null : e.delCuit.firstWhere((p) => p.id == elegido);
        await _proponer(e, conIa: true);
      }
    } on ErrorGemini catch (x) {
      error = x.mensaje;
    } finally {
      leyendo = false;
      _avisar();
    }
  }

  /// Propone los vínculos de [e] con lo aprendido de su proveedor y, si hay clave, le pide a la IA ayuda con lo que quedó sin vincular.
  Future<void> _proponer(EstadoFactura e, {required bool conIa}) async {
    final lineas = [for (final l in e.n.lineas) LineaAVincular(codigo: l.codigo, descripcion: l.descripcion)];
    final vinculos = e.proveedor == null ? const <VinculoAprendido>[] : await vinculosDe(db, e.proveedor!.id);
    var propuestas = proponerVinculos(lineas: lineas, catalogo: catalogo, vinculos: vinculos, proveedorId: e.proveedor?.id);
    await _tomarPropuestas(e, propuestas);

    final pendientes = [
      for (var i = 0; i < propuestas.length; i++)
        if (propuestas[i].confianza == ConfianzaVinculo.ninguna) (posicion: i, linea: lineas[i]),
    ];
    final candidatosIa = candidatosParaIa(catalogo, e.proveedor?.id, propuestas);
    if (!conIa || !ClaveGemini.configurada || pendientes.isEmpty || candidatosIa.isEmpty || _cerrado) return;
    e.consultandoIa = true;
    _avisar();
    final cliente = ClienteGemini.guardado(client: clienteIa);
    try {
      final sugerencias = await vincularConIa(cliente, pendientes: pendientes, candidatos: candidatosIa);
      propuestas = conSugerenciasDeIa(propuestas, sugerencias, idsDelCatalogo: {for (final c in catalogo) c.id});
      await _tomarPropuestas(e, propuestas);
    } on ErrorGemini catch (x) {
      e.avisoIa = 'La IA no pudo ayudar con los vínculos (${x.mensaje}). Elegí a mano lo que falte.';
    } finally {
      cliente.close();
      e.consultandoIa = false;
      _avisar();
    }
  }

  Future<void> _tomarPropuestas(EstadoFactura e, List<PropuestaDeVinculo> propuestas) async {
    if (_cerrado) return;
    // Los productos que se ofrecen en cada línea: los del proveedor, las alternativas y lo elegido. Sin proveedor conocido, todo el catálogo.
    final ids = <int>{
      for (final c in catalogo)
        if (e.proveedor != null && c.proveedorId == e.proveedor!.id) c.id,
      for (final p in propuestas) ...p.alternativas,
      for (final p in propuestas) ?p.productoId,
    };
    final candidatos = ids.length < 5 ? catalogo.take(400).toList() : [for (final c in catalogo) if (ids.contains(c.id)) c];
    candidatos.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    e.propuestas = propuestas;
    e.producto = [for (final p in propuestas) p.productoId];
    e.multiplicador = [for (final p in propuestas) p.unidadesPorCantidad];
    e.motivoUnidades = {};
    _sugerirUnidades(e);
    e.candidatos = candidatos;
    if (e.noVa.length != propuestas.length) e.noVa = List.filled(propuestas.length, false);
    e.version++;
    _avisar();
    await _revisarPrecios(e);
  }

  /// El costo de cada línea con las unidades elegidas, o null si los importes no permiten calcularlo.
  (FacturaDeCompra, List<CostoDeLinea>)? costosDe(EstadoFactura e) {
    try {
      final f = e.multiplicador.length == e.n.factura.lineas.length ? conUnidadesPorCantidad(e.n.factura, e.multiplicador) : e.n.factura;
      return (f, costosDeFactura(f));
    } on ArgumentError {
      return null;
    }
  }

  List<LineaParaAplicar>? lineasParaAplicar(EstadoFactura e) {
    final c = costosDe(e);
    if (c == null) return null;
    final (f, costos) = c;
    return [
      for (var i = 0; i < costos.length; i++)
        LineaParaAplicar(
          productoId: i < e.producto.length ? e.producto[i] : null,
          unidades: f.lineas[i].unidades,
          totalCentavos: costos[i].totalCentavos,
          noVa: i < e.noVa.length && e.noVa[i],
        ),
    ];
  }

  /// Avisa en rojo, ANTES de aplicar, las líneas cuyo producto quedaría vendiéndose por menos de lo que costó (precio fijo o
  /// cigarrillos: el precio no se toca; con el % del proveedor sube solo y no hace falta avisar).
  Future<void> _revisarPrecios(EstadoFactura e) async {
    final c = costosDe(e);
    if (c == null) return;
    final (_, costos) = c;
    final avisos = <int, String>{};
    for (var i = 0; i < costos.length; i++) {
      final id = i < e.producto.length ? e.producto[i] : null;
      if (id == null || (i < e.noVa.length && e.noVa[i])) continue;
      final p = await (db.select(db.productos)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (p == null || p.esPesable) continue;
      final costo = costos[i].costoUnitarioCentavos;
      final precio = await precioTrasCambioDeCosto(db, p, costoNuevoCentavos: costo);
      if (precio != null && costo > precio) {
        avisos[i] = 'Pierde plata: cuesta ${formatearARS(costo)} y lo vendés a ${formatearARS(precio)}. Cambiá el precio después de aplicar.';
      }
    }
    e.avisosPrecio = avisos;
    _avisar();
  }

  /// El dueño eligió otro producto para la línea: otro costo para comparar, se vuelve a proponer el bulto de esa línea.
  Future<void> elegirProducto(EstadoFactura e, int linea, int? id) async {
    e.producto[linea] = id;
    _sugerirUnidades(e, lineas: {linea});
    e.version++;
    _avisar();
    await _revisarPrecios(e);
  }

  Future<void> cambiarUnidades(EstadoFactura e, int linea, int n) async {
    e.multiplicador[linea] = n < 1 ? 1 : n;
    _avisar();
    await _revisarPrecios(e);
  }

  Future<void> marcarNoVa(EstadoFactura e, int linea, bool v) async {
    e.noVa[linea] = v;
    _avisar();
    await _revisarPrecios(e);
  }

  void sumarStock(EstadoFactura e, bool v) {
    e.sumarStock = v;
    _avisar();
  }

  void cambiarProveedor(EstadoFactura e) {
    e.proveedor = null;
    _avisar();
  }

  /// Aplica la factura (stock, costo y deuda) y aprende los vínculos confirmados. Devuelve true si se aplicó; si no, el motivo queda en
  /// `e.errorAplicar`. Si la factura no cierra ([EstadoFactura.hayQueConfirmar]), la pantalla le pregunta al dueño ANTES de llamar acá.
  Future<bool> aplicar(EstadoFactura e, {required int usuarioId}) async {
    final lineas = lineasParaAplicar(e);
    if (lineas == null) {
      e.errorAplicar = 'No se pudieron calcular los costos: revisá los importes de la factura.';
      _avisar();
      return false;
    }
    final f = e.n.leida;
    final motivos = motivosParaNoAplicar(proveedorId: e.proveedor?.id, tipo: f.tipo, lineas: lineas);
    if (motivos.isNotEmpty) {
      e.errorAplicar = motivos.join('\n');
      _avisar();
      return false;
    }
    e.aplicando = true;
    e.errorAplicar = null;
    _avisar();
    try {
      final r = await aplicarFactura(
        db,
        proveedorId: e.proveedor!.id,
        numero: f.numero,
        tipo: f.tipo,
        fecha: f.fecha,
        condicionPago: f.condicionPago,
        totalImpresoCentavos: f.pie.totalCentavos,
        lineas: lineas,
        sumarStock: e.sumarStock,
        usuarioId: usuarioId,
      );
      // Aplicar confirma los vínculos: se aprenden, así la próxima factura de este proveedor sale sola.
      for (var i = 0; i < lineas.length; i++) {
        final id = lineas[i].productoId;
        if (id == null || lineas[i].noVa) continue;
        await aprenderVinculo(db, proveedorId: e.proveedor!.id, productoId: id, codigo: e.n.lineas[i].codigo, descripcion: e.n.lineas[i].descripcion, unidadesPorCantidad: e.multiplicador[i]);
      }
      final total = montoDeLaDeuda(totalImpresoCentavos: f.pie.totalCentavos, lineas: lineas);
      e.facturaAplicadaId = r.facturaId;
      e.resumenAplicada = [
        'Aplicada: ${r.productos} producto(s)${e.sumarStock ? ' con stock' : ', sin tocar el stock'}, y ${formatearARS(total)} en la cuenta corriente de ${e.proveedor!.nombre}.',
        if (r.pesablesSinTocar.isNotEmpty) 'Por peso, cargalos a mano: ${r.pesablesSinTocar.join(', ')}.',
      ].join(' ');
      return true;
    } on FacturaYaCargadaException catch (x) {
      e.errorAplicar = x.toString();
      return false;
    } on ArgumentError catch (x) {
      e.errorAplicar = '${x.message}';
      return false;
    } finally {
      e.aplicando = false;
      _avisar();
    }
  }

  /// Deshace la factura recién aplicada. Devuelve el aviso para mostrar, o null si no se pudo (el motivo queda en `e.errorAplicar`).
  Future<String?> deshacer(EstadoFactura e, {required int usuarioId}) async {
    final id = e.facturaAplicadaId;
    if (id == null) return null;
    try {
      final r = await deshacerFactura(db, facturaId: id, usuarioId: usuarioId);
      e.facturaAplicadaId = null;
      e.resumenAplicada = null;
      _avisar();
      return r.costosQueQuedaron.isEmpty ? 'Factura deshecha' : 'Factura deshecha. El costo de ${r.costosQueQuedaron.join(', ')} quedó como lo cambiaste.';
    } on ArgumentError catch (x) {
      e.errorAplicar = '${x.message}';
      _avisar();
      return null;
    }
  }

  /// Bultos vs. unidades: donde el vínculo no está aprendido, propone el "× unid." con la descripción y el costo que ya tenés cargado.
  /// Solo propone — el dueño lo ve y lo corrige —, y lo aprendido manda siempre.
  void _sugerirUnidades(EstadoFactura e, {Set<int>? lineas}) {
    final List<CostoDeLinea> base;
    try {
      base = costosDeFactura(e.n.factura);
    } on ArgumentError {
      return;
    }
    final porId = {for (final c in catalogo) c.id: c};
    for (var i = 0; i < e.n.lineas.length; i++) {
      if (lineas != null && !lineas.contains(i)) continue;
      final id = i < e.producto.length ? e.producto[i] : null;
      if (id == null) continue;
      if (i < e.propuestas.length && e.propuestas[i].origen == OrigenVinculo.aprendido && e.propuestas[i].productoId == id) continue;
      final inferido = inferirUnidadesPorCantidad(
        costoPorCantidadCentavos: base[i].costoUnitarioCentavos,
        costoActualPorUnidadCentavos: porId[id]?.costoCentavos,
        packSugerido: sugerirUnidadesPorBulto(e.n.lineas[i].descripcion),
      );
      if (inferido == null) {
        // Sin costo para comparar, la descripción sola solo sirve de aviso: no se pre-llena un bulto a ciegas.
        final pack = sugerirUnidadesPorBulto(e.n.lineas[i].descripcion);
        e.multiplicador[i] = 1;
        if (pack != null) {
          e.motivoUnidades[i] = 'La descripción menciona un pack de $pack. Si la factura cuenta bultos, poné $pack en "× unid.".';
        } else {
          e.motivoUnidades.remove(i);
        }
        continue;
      }
      e.multiplicador[i] = inferido.unidades;
      e.motivoUnidades[i] = inferido.unidades > 1 ? 'Bulto de ${inferido.unidades}: ${inferido.motivo}' : inferido.motivo;
    }
  }

  Future<void> elegirProveedor(EstadoFactura e, int proveedorId) async {
    final proveedor = proveedores.firstWhere((p) => p.id == proveedorId);
    // Se suma al CUIT, no se lo saca a otro proveedor que ya lo tenía.
    await asociarCuit(db, proveedorId: proveedor.id, cuit: e.n.leida.proveedorCuit);
    if (!e.delCuit.any((p) => p.id == proveedor.id) && cuitNormalizado(e.n.leida.proveedorCuit) != null) e.delCuit = [...e.delCuit, proveedor];
    e.proveedor = proveedor;
    await _proponer(e, conIa: true);
  }

  /// Lo que se precarga al crear el producto que falta desde la línea [linea]: nombre armado con las palabras del catálogo, código de
  /// barras si viene y el costo por unidad (null si los importes están mal leídos: se carga a mano).
  ({String nombre, String? codigoBarras, int? costoCentavos}) datosParaCrear(EstadoFactura e, int linea) {
    final l = e.n.lineas[linea];
    int? costo;
    try {
      costo = costosDeFactura(conUnidadesPorCantidad(e.n.factura, e.multiplicador))[linea].costoUnitarioCentavos;
    } on ArgumentError {
      costo = null;
    }
    return (
      nombre: nombreSugeridoDesdeFactura(l.descripcion, nombresDelCatalogo: [for (final c in catalogo) c.nombre]),
      codigoBarras: codigoDeBarrasDeLinea(l.codigo),
      costoCentavos: costo,
    );
  }

  /// "Mejorar nombre con IA" para el producto de la línea [linea]; null sin clave.
  Future<String> Function()? mejorarNombre(EstadoFactura e, int linea) {
    if (!ClaveGemini.configurada) return null;
    return () async {
      // De ejemplo de estilo, primero los productos del mismo proveedor (se cargan parecido).
      final ejemplos = [
        for (final c in catalogo) if (c.proveedorId == e.proveedor?.id) c.nombre,
        for (final c in catalogo) if (c.proveedorId != e.proveedor?.id) c.nombre,
      ];
      final cliente = ClienteGemini.guardado(client: clienteIa);
      try {
        return await mejorarNombreConIa(cliente, descripcion: e.n.lineas[linea].descripcion, ejemplos: ejemplos);
      } finally {
        cliente.close();
      }
    };
  }

  /// El producto [id] se acaba de crear desde la línea [linea]: entra al catálogo y la línea queda vinculada a él.
  Future<void> productoCreado(EstadoFactura e, int linea, int id) async {
    catalogo = await catalogoParaVincular(db);
    final nuevo = catalogo.where((c) => c.id == id).firstOrNull;
    e.producto[linea] = id;
    if (nuevo != null && !e.candidatos.any((x) => x.id == id)) {
      e.candidatos = [...e.candidatos, nuevo]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    }
    e.version++;
    _avisar();
    await _revisarPrecios(e);
  }

  /// "Aprender estos vínculos": guarda lo elegido en cada línea para la próxima factura de este proveedor.
  Future<void> aprender(EstadoFactura e) async {
    final proveedor = e.proveedor;
    if (proveedor == null) return;
    var n = 0;
    for (var i = 0; i < e.n.lineas.length; i++) {
      final id = e.producto[i];
      if (id == null) continue;
      await aprenderVinculo(
        db,
        proveedorId: proveedor.id,
        productoId: id,
        codigo: e.n.lineas[i].codigo,
        descripcion: e.n.lineas[i].descripcion,
        unidadesPorCantidad: e.multiplicador[i],
      );
      n++;
    }
    await _proponer(e, conIa: false);
    e.avisoAprendido = 'Aprendí $n vínculo(s) de ${proveedor.nombre}: la próxima factura sale sola.';
    _avisar();
  }

  /// Lo que contestó la IA, en JSON legible ("Copiar lectura"); null si todavía no se leyó nada.
  String? get lecturaEnJson => resultado == null ? null : const JsonEncoder.withIndent('  ').convert(resultado!.json);
}
