// "Leer una factura (prueba)" (El dueño, 2026-10-05): elegís fotos o PDF de facturas de compra, la IA las transcribe y ves el costo real
// de cada producto, si la factura cierra con su total y con qué producto de tu base se vincula cada línea. TODAVÍA NO TOCA costos, stock ni
// deuda: lo único que guarda es lo que "aprende" (vínculos y CUIT del proveedor), para que la próxima factura salga vinculada sola.
// "Copiar lectura" deja el JSON de la IA en el portapapeles. Plan en `docs/PLAN-FACTURAS.md`.

import 'dart:convert';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../comun/aviso_superior.dart';
import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show listarProveedores;
import '../../data/repositorio_vinculos_factura.dart';
import '../../domain/dinero.dart';
import '../../domain/factura_compra.dart';
import '../../domain/lectura_factura.dart';
import '../../domain/unidades_bulto.dart';
import '../../servicios/gemini.dart';
import '../../servicios/lector_facturas.dart';
import '../../domain/vinculo_factura.dart';
import '../../servicios/preparar_imagen.dart';
import '../../servicios/vinculador_ia.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../configuracion/seccion_asistente_ia.dart' show SelectorModeloIa;
import '../tema/acentos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../tema/iconos.dart';
import 'dialogo_editar_producto.dart';
import 'proveedores_controlador.dart';

/// [clienteIa] y [adjuntosIniciales] son solo para tests: el selector de archivos es nativo y no se puede manejar desde un test.
/// [controlador] habilita "crear producto" en las líneas que no están en el catálogo (usa el mismo alta que Proveedores).
Future<void> mostrarDialogoLeerFactura(
  BuildContext context, {
  required AppDatabase db,
  ProveedoresControlador? controlador,
  http.Client? clienteIa,
  List<AdjuntoGemini> adjuntosIniciales = const [],
}) {
  return mostrarModal<void>(
    context,
    builder: (_) => _DialogoLeerFactura(db: db, controlador: controlador, clienteIa: clienteIa, adjuntosIniciales: adjuntosIniciales),
  );
}

/// Todo lo de una factura leída: el proveedor, la propuesta de vínculos y lo que el dueño fue eligiendo.
class _EstadoFactura {
  _EstadoFactura(this.n);

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
  List<DropdownMenuEntry<int>> entradas = const [];

  /// Sube cada vez que se vuelve a proponer: obliga a los campos a tomar los valores nuevos.
  int version = 0;
  bool consultandoIa = false;
  String? avisoIa;
  String? avisoAprendido;

  int get vinculadas => producto.where((p) => p != null).length;
}

class _DialogoLeerFactura extends StatefulWidget {
  const _DialogoLeerFactura({required this.db, this.controlador, this.clienteIa, this.adjuntosIniciales = const []});

  final AppDatabase db;
  final ProveedoresControlador? controlador;
  final http.Client? clienteIa;
  final List<AdjuntoGemini> adjuntosIniciales;

  @override
  State<_DialogoLeerFactura> createState() => _DialogoLeerFacturaState();
}

class _DialogoLeerFacturaState extends State<_DialogoLeerFactura> {
  late final List<AdjuntoGemini> _adjuntos = [...widget.adjuntosIniciales];
  late final List<String> _nombres = [for (var i = 0; i < widget.adjuntosIniciales.length; i++) 'archivo ${i + 1}'];
  bool _leyendo = false;
  String? _error;
  ResultadoDeLectura? _resultado;
  List<_EstadoFactura> _facturas = const [];
  List<ProductoCandidato> _catalogo = const [];
  List<Proveedor> _proveedores = const [];

  Future<void> _elegir() async {
    final archivos = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Fotos y PDF', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf']),
      ],
    );
    if (archivos.isEmpty) return;
    setState(() {
      _error = null;
      _leyendo = true;
    });
    final nuevos = <AdjuntoGemini>[];
    final nombres = <String>[];
    for (final f in archivos) {
      final adjunto = await prepararArchivoDeFactura(f.name, await f.readAsBytes());
      if (adjunto == null) {
        _error = 'No pude abrir "${f.name}": tiene que ser una foto o un PDF.';
        continue;
      }
      nuevos.add(adjunto);
      nombres.add('${f.name} (${(adjunto.bytes.length / 1024).round()} KB)');
    }
    if (!mounted) return;
    setState(() {
      _adjuntos
        ..clear()
        ..addAll(nuevos);
      _nombres
        ..clear()
        ..addAll(nombres);
      _resultado = null;
      _facturas = const [];
      _leyendo = false;
    });
  }

  Future<void> _leer() async {
    setState(() {
      _leyendo = true;
      _error = null;
      _resultado = null;
      _facturas = const [];
    });
    try {
      final r = await leerFacturasConGemini(_adjuntos, client: widget.clienteIa);
      _catalogo = await catalogoParaVincular(widget.db);
      _proveedores = [for (final p in await listarProveedores(widget.db)) if (p.activo) p];
      final estados = [for (final f in r.lectura.facturas) _EstadoFactura(normalizarFactura(f))];
      if (!mounted) return;
      setState(() {
        _resultado = r;
        _facturas = estados;
        _leyendo = false;
      });
      for (final e in estados) {
        e.delCuit = [for (final p in await proveedoresPorCuit(widget.db, e.n.leida.proveedorCuit)) if (p.activo) p];
        final ids = [for (final p in e.delCuit) p.id];
        // Con varios proveedores para el mismo CUIT decide lo que trae la factura; si no se puede decidir, se pregunta.
        final elegido = elegirProveedorDeFactura(
          candidatos: ids,
          lineas: [for (final l in e.n.lineas) LineaAVincular(codigo: l.codigo, descripcion: l.descripcion)],
          catalogo: _catalogo,
          vinculosPorProveedor: await vinculosDeVarios(widget.db, ids),
        );
        e.proveedor = elegido == null ? null : e.delCuit.firstWhere((p) => p.id == elegido);
        await _proponer(e, conIa: true);
      }
    } on ErrorGemini catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  /// Propone los vínculos de [e] con lo aprendido de su proveedor y, si hay clave, le pide a la IA ayuda con lo que quedó sin vincular.
  Future<void> _proponer(_EstadoFactura e, {required bool conIa}) async {
    final lineas = [for (final l in e.n.lineas) LineaAVincular(codigo: l.codigo, descripcion: l.descripcion)];
    final vinculos = e.proveedor == null ? const <VinculoAprendido>[] : await vinculosDe(widget.db, e.proveedor!.id);
    var propuestas = proponerVinculos(lineas: lineas, catalogo: _catalogo, vinculos: vinculos, proveedorId: e.proveedor?.id);
    _aplicar(e, propuestas);

    final pendientes = [
      for (var i = 0; i < propuestas.length; i++)
        if (propuestas[i].confianza == ConfianzaVinculo.ninguna) (posicion: i, linea: lineas[i]),
    ];
    final candidatos = candidatosParaIa(_catalogo, e.proveedor?.id, propuestas);
    if (!conIa || !ClaveGemini.configurada || pendientes.isEmpty || candidatos.isEmpty) return;
    if (mounted) setState(() => e.consultandoIa = true);
    final cliente = ClienteGemini.guardado(client: widget.clienteIa);
    try {
      final sugerencias = await vincularConIa(cliente, pendientes: pendientes, candidatos: candidatos);
      propuestas = conSugerenciasDeIa(propuestas, sugerencias, idsDelCatalogo: {for (final c in _catalogo) c.id});
      _aplicar(e, propuestas);
    } on ErrorGemini catch (x) {
      e.avisoIa = 'La IA no pudo ayudar con los vínculos (${x.mensaje}). Elegí a mano lo que falte.';
    } finally {
      cliente.close();
      if (mounted) setState(() => e.consultandoIa = false);
    }
  }

  void _aplicar(_EstadoFactura e, List<PropuestaDeVinculo> propuestas) {
    if (!mounted) return;
    // Los productos que se ofrecen en cada línea: los del proveedor, las alternativas y lo elegido. Sin proveedor conocido, todo el catálogo.
    final ids = <int>{
      for (final c in _catalogo)
        if (e.proveedor != null && c.proveedorId == e.proveedor!.id) c.id,
      for (final p in propuestas) ...p.alternativas,
      for (final p in propuestas) ?p.productoId,
    };
    final candidatos = ids.length < 5 ? _catalogo.take(400).toList() : [for (final c in _catalogo) if (ids.contains(c.id)) c];
    candidatos.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    setState(() {
      e.propuestas = propuestas;
      e.producto = [for (final p in propuestas) p.productoId];
      e.multiplicador = [for (final p in propuestas) p.unidadesPorCantidad];
      e.motivoUnidades = {};
      _sugerirUnidades(e);
      e.entradas = [for (final c in candidatos) DropdownMenuEntry<int>(value: c.id, label: c.nombre)];
      e.version++;
    });
  }

  /// Bultos vs. unidades: donde el vínculo no está aprendido, propone el "× unid." con la descripción y el costo que ya tenés cargado.
  /// Solo propone — el dueño lo ve y lo corrige —, y lo aprendido manda siempre.
  void _sugerirUnidades(_EstadoFactura e, {Set<int>? lineas}) {
    final List<CostoDeLinea> base;
    try {
      base = costosDeFactura(e.n.factura);
    } on ArgumentError {
      return;
    }
    final porId = {for (final c in _catalogo) c.id: c};
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

  Future<void> _elegirProveedor(_EstadoFactura e, int proveedorId) async {
    final proveedor = _proveedores.firstWhere((p) => p.id == proveedorId);
    // Se suma al CUIT, no se lo saca a otro proveedor que ya lo tenía.
    await asociarCuit(widget.db, proveedorId: proveedor.id, cuit: e.n.leida.proveedorCuit);
    if (!e.delCuit.any((p) => p.id == proveedor.id) && cuitNormalizado(e.n.leida.proveedorCuit) != null) e.delCuit = [...e.delCuit, proveedor];
    e.proveedor = proveedor;
    await _proponer(e, conIa: true);
  }

  /// Una línea que no está en el catálogo (o que el parecido vinculó con otro producto parecido, "XB BOX" con "XB convertible BOX"): se da de
  /// alta con el formulario de siempre, precargado con lo leído — nombre, costo por unidad, proveedor y código de barras si viene —, y la
  /// línea queda vinculada al producto nuevo.
  Future<void> _crearProducto(_EstadoFactura e, int linea) async {
    final controlador = widget.controlador;
    if (controlador == null) return;
    final l = e.n.lineas[linea];
    int? costo;
    try {
      costo = costosDeFactura(conUnidadesPorCantidad(e.n.factura, e.multiplicador))[linea].costoUnitarioCentavos;
    } on ArgumentError {
      costo = null; // importes mal leídos: el costo se carga a mano
    }
    final id = await mostrarDialogoEditarProducto(
      context,
      controlador: controlador,
      proveedorIdPreseleccionado: e.proveedor?.id,
      inicial: DatosProductoNuevo(nombre: nombreSugeridoDesdeFactura(l.descripcion), codigoBarras: codigoDeBarrasDeLinea(l.codigo), costoCentavos: costo),
    );
    if (id == null || !mounted) return;
    _catalogo = await catalogoParaVincular(widget.db);
    final nuevo = _catalogo.where((c) => c.id == id).firstOrNull;
    if (!mounted) return;
    setState(() {
      e.producto[linea] = id;
      if (nuevo != null && !e.entradas.any((x) => x.value == id)) {
        e.entradas = [...e.entradas, DropdownMenuEntry<int>(value: id, label: nuevo.nombre)]
          ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      }
      e.version++;
    });
  }

  Future<void> _aprender(_EstadoFactura e) async {
    final proveedor = e.proveedor;
    if (proveedor == null) return;
    var n = 0;
    for (var i = 0; i < e.n.lineas.length; i++) {
      final id = e.producto[i];
      if (id == null) continue;
      await aprenderVinculo(
        widget.db,
        proveedorId: proveedor.id,
        productoId: id,
        codigo: e.n.lineas[i].codigo,
        descripcion: e.n.lineas[i].descripcion,
        unidadesPorCantidad: e.multiplicador[i],
      );
      n++;
    }
    if (!mounted) return;
    setState(() => e.avisoAprendido = 'Aprendí $n vínculo(s) de ${proveedor.nombre}: la próxima factura sale sola.');
    await _proponer(e, conIa: false);
    if (mounted) setState(() => e.avisoAprendido = 'Aprendí $n vínculo(s) de ${proveedor.nombre}: la próxima factura sale sola.');
  }

  Future<void> _copiar() async {
    final r = _resultado;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(r.json)));
    if (!mounted) return;
    mostrarAviso(context, 'Lectura copiada al portapapeles');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    // El contenido scrollea adentro del diálogo: se le deja casi todo el alto de la ventana (menos título y botones).
    final alto = math.max(320.0, MediaQuery.sizeOf(context).height - 330);
    return Modal(
      titulo: 'Leer una factura (prueba)',
      subtitulo: 'Elegí fotos o PDF. La IA las lee y la vinculás con tus productos. Todavía no toca costos, stock ni deuda.',
      ancho: 1180,
      contenido: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BarraDeLectura(
                nombres: _nombres,
                leyendo: _leyendo,
                error: _error,
                onCambioModelo: () => setState(() {}),
              ),
              if (_resultado != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.lg),
                  child: Row(
                    children: [
                      Expanded(child: Text('Leído con ${_resultado!.modelo}', style: textTheme.bodySmall?.copyWith(color: colores.textoTenue))),
                      // El Modal admite 3 botones como máximo: esta acción va acá y no abajo.
                      TextButton(onPressed: _copiar, child: const Text('Copiar lectura')),
                    ],
                  ),
                ),
                for (final a in _resultado!.lectura.advertencias) Text(a, style: textTheme.bodySmall),
                for (var i = 0; i < _facturas.length; i++)
                  _TarjetaFactura(
                    indice: i,
                    e: _facturas[i],
                    proveedores: _proveedores,
                    nombresDeProductos: {for (final c in _catalogo) c.id: c.nombre},
                    onProveedor: (id) => _elegirProveedor(_facturas[i], id),
                    onCambiarProveedor: () => setState(() => _facturas[i].proveedor = null),
                    onProducto: (linea, id) => setState(() {
                      _facturas[i].producto[linea] = id;
                      // Otro producto, otro costo para comparar: se vuelve a proponer el bulto de esa línea.
                      _sugerirUnidades(_facturas[i], lineas: {linea});
                      _facturas[i].version++;
                    }),
                    onUnidades: (linea, n) => setState(() => _facturas[i].multiplicador[linea] = n < 1 ? 1 : n),
                    onAprender: () => _aprender(_facturas[i]),
                    onCrearProducto: widget.controlador == null ? null : (linea) => _crearProducto(_facturas[i], linea),
                  ),
              ],
            ],
          ),
        ),
      ),
      botones: [
        BotonSecundario(texto: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        BotonSecundario(texto: 'Elegir archivos', onPressed: _leyendo ? null : _elegir),
        BotonPrimario(
          texto: _leyendo ? 'Leyendo…' : 'Leer con IA',
          onPressed: _leyendo || _adjuntos.isEmpty || !ClaveGemini.configurada ? null : _leer,
        ),
      ],
    );
  }
}

String _nombreDelModo(ModoImportes m) => switch (m) {
  ModoImportes.neto => 'importes sin IVA',
  ModoImportes.conIva => 'importes con el IVA adentro',
  ModoImportes.conIvaEInternos => 'importes con IVA e impuestos internos adentro',
  ModoImportes.todoIncluido => 'importes finales (IVA, impuestos y percepciones ya adentro)',
};

/// Lo de arriba: qué archivos hay, con qué modelo se lee y cómo va la lectura. Una sola superficie, como las demás pantallas.
class _BarraDeLectura extends StatelessWidget {
  const _BarraDeLectura({required this.nombres, required this.leyendo, required this.error, required this.onCambioModelo});

  final List<String> nombres;
  final bool leyendo;
  final String? error;
  final VoidCallback onCambioModelo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    return Superficie(
      padding: const EdgeInsets.all(Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ClaveGemini.configurada)
            Text('Falta la clave de la IA: cargala en Configuración › Asistente IA.', style: textTheme.bodyMedium?.copyWith(color: colores.error))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: nombres.isEmpty
                      ? Text('Todavía no elegiste nada.', style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario))
                      : Wrap(spacing: Espaciado.sm, runSpacing: Espaciado.xs, children: [for (final n in nombres) Insignia(texto: n)]),
                ),
                const SizedBox(width: Espaciado.lg),
                // Mientras se prueba, el modelo se cambia acá mismo: es el mismo ajuste que en Configuración › Asistente IA.
                SelectorModeloIa(onCambio: onCambioModelo),
              ],
            ),
          if (leyendo) const Padding(padding: EdgeInsets.only(top: Espaciado.md), child: LinearProgressIndicator()),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Espaciado.md),
              child: Text(error!, style: textTheme.bodyMedium?.copyWith(color: colores.error)),
            ),
        ],
      ),
    );
  }
}

// Las columnas de la tabla de líneas: el encabezado y cada fila comparten estos anchos para que todo quede alineado.
// La descripción de la factura y el producto tuyo se reparten lo que sobra.
const double _anchoCantidad = 56;
const double _anchoMultiplo = 92;
const double _anchoUnidades = 92;
const double _anchoTotal = 108;
const double _anchoCostoUnidad = 124;

class _TarjetaFactura extends StatelessWidget {
  const _TarjetaFactura({
    required this.indice,
    required this.e,
    required this.proveedores,
    required this.nombresDeProductos,
    required this.onProveedor,
    required this.onCambiarProveedor,
    required this.onProducto,
    required this.onUnidades,
    required this.onAprender,
    this.onCrearProducto,
  });

  final int indice;
  final _EstadoFactura e;
  final List<Proveedor> proveedores;
  final Map<int, String> nombresDeProductos;
  final ValueChanged<int> onProveedor;
  final VoidCallback onCambiarProveedor;
  final void Function(int linea, int? productoId) onProducto;
  final void Function(int linea, int unidades) onUnidades;
  final VoidCallback onAprender;
  final ValueChanged<int>? onCrearProducto;

  @override
  Widget build(BuildContext context) {
    final n = e.n;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final f = n.leida;
    List<CostoDeLinea>? costos;
    try {
      costos = e.multiplicador.length == n.factura.lineas.length
          ? costosDeFactura(conUnidadesPorCantidad(n.factura, e.multiplicador))
          : costosDeFactura(n.factura);
    } on ArgumentError {
      costos = null; // por ejemplo, un descuento mayor que la factura: está mal leído
    }
    final control = n.control;
    final detalle = [
      if (f.tipo != null) 'Factura ${f.tipo}',
      if (f.numero != null) f.numero!,
      if (f.fecha != null) '${f.fecha!.day}/${f.fecha!.month}/${f.fecha!.year}',
      if (f.condicionPago != null) f.condicionPago == 'contado' ? 'contado' : 'cuenta corriente',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.lg),
      child: Superficie(
        padding: const EdgeInsets.all(Espaciado.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.proveedorNombre ?? 'Factura', style: textTheme.titleLarge),
                      if (detalle.isNotEmpty) Text(detalle, style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
                    ],
                  ),
                ),
                if (f.pie.totalCentavos != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total impreso', style: textTheme.labelMedium?.copyWith(color: colores.textoTenue)),
                      Text(formatearARS(f.pie.totalCentavos!), style: textTheme.titleLarge),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: Espaciado.md),
            Wrap(
              spacing: Espaciado.sm,
              runSpacing: Espaciado.xs,
              children: [
                if (control == null)
                  const Insignia(texto: 'Sin total impreso: no se puede controlar', tono: Tono.alerta)
                else if (n.cierraConRedondeo)
                  Insignia(
                    texto: 'Cierra con redondeo de impresión (diferencia de ${formatearARS(control.diferenciaCentavos.abs())})',
                    tono: Tono.alerta,
                  )
                else if (n.cierra)
                  const Insignia(texto: 'Cierra con el total impreso', tono: Tono.ganancia)
                else
                  Insignia(texto: 'No cierra: diferencia de ${formatearARS(control.diferenciaCentavos.abs())} — revisá', tono: Tono.error),
                Insignia(
                  texto: n.modo == ModoImportes.neto && n.lineas.isNotEmpty && n.lineas.every((l) => l.alicuotaBp == 0)
                      ? 'importes finales (el IVA no está discriminado)'
                      : _nombreDelModo(n.modo),
                ),
                if (e.proveedor != null) Insignia(texto: 'Proveedor: ${e.proveedor!.nombre}', tono: Tono.ganancia),
                if (fechaDudosa(f.fecha, DateTime.now()))
                  Insignia(texto: 'La fecha (${f.fecha!.day}/${f.fecha!.month}/${f.fecha!.year}) parece mal leída: revisala', tono: Tono.error),
              ],
            ),
            for (final a in f.advertencias) Padding(padding: const EdgeInsets.only(top: Espaciado.xs), child: Text(a, style: textTheme.bodySmall)),
            if (e.producto.isNotEmpty) _ResumenDeVinculos(propuestas: e.propuestas, elegidos: e.producto),
            if (e.proveedor == null)
              _ElegirProveedor(indice: indice, cuit: f.proveedorCuit, delCuit: e.delCuit, proveedores: proveedores, onElegir: onProveedor)
            else
              // Se equivocó de proveedor (o es la otra cuenta del mismo mayorista): se puede cambiar antes de aprender.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(key: ValueKey('cambiar_proveedor_$indice'), onPressed: onCambiarProveedor, child: const Text('Cambiar proveedor')),
              ),
            const SizedBox(height: Espaciado.md),
            // La tabla va sobre el fondo de la ventana (blanco) para que se despegue de la tarjeta gris, como los bloques de las otras pantallas.
            Container(
              padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.md, Espaciado.lg, Espaciado.md),
              decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(Espaciado.xl)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _EncabezadoDeLineas(),
                  if (costos == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Espaciado.md),
                      child: Text('No se pudieron calcular los costos: revisá los importes de la factura.', style: textTheme.bodySmall?.copyWith(color: colores.error)),
                    )
                  else
                    for (var i = 0; i < costos.length; i++)
                      _FilaLinea(
                        key: ValueKey('linea_${indice}_$i'),
                        descripcion: n.lineas[i].descripcion,
                        sospechosa: n.lineasSospechosas.contains(i),
                        propuesta: i < e.propuestas.length ? e.propuestas[i] : null,
                        elegido: i < e.producto.length ? e.producto[i] : null,
                        unidades: i < e.multiplicador.length ? e.multiplicador[i] : 1,
                        motivoUnidades: e.motivoUnidades[i],
                        cantidad: n.factura.lineas[i].unidades,
                        version: e.version,
                        entradas: e.entradas,
                        costo: costos[i],
                        onProducto: (id) => onProducto(i, id),
                        onUnidades: (u) => onUnidades(i, u),
                        onCrear: onCrearProducto == null ? null : () => onCrearProducto!(i),
                      ),
                ],
              ),
            ),
            const SizedBox(height: Espaciado.md),
            Row(
              children: [
                TextButton(
                  key: ValueKey('aprender_$indice'),
                  style: TextButton.styleFrom(
                    backgroundColor: colores.fondo,
                    foregroundColor: colores.textoPrimario,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
                  ),
                  onPressed: e.proveedor != null && e.vinculadas > 0 ? onAprender : null,
                  child: Text('Aprender estos vínculos (${e.vinculadas})'),
                ),
                const SizedBox(width: Espaciado.md),
                if (e.avisoAprendido != null) Expanded(child: Text(e.avisoAprendido!, style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario))),
              ],
            ),
            if (e.avisoIa != null) Padding(padding: const EdgeInsets.only(top: Espaciado.xs), child: Text(e.avisoIa!, style: textTheme.bodySmall)),
            const SizedBox(height: Espaciado.md),
            Text(
              [
                if (f.pie.descuentoGlobalCentavos > 0) 'Descuento ${formatearARS(f.pie.descuentoGlobalCentavos)}',
                if (f.pie.percepcionesCentavos > 0) 'Percepciones ${formatearARS(f.pie.percepcionesCentavos)}',
                if (f.pie.internosCentavos > 0) 'Impuestos internos ${formatearARS(f.pie.internosCentavos)}',
                if (control != null) 'Total calculado ${formatearARS(control.totalCalculadoCentavos)}',
              ].join(' · '),
              style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
            ),
            Text(
              'El costo por unidad incluye IVA e impuestos y lo repartido del pie. Verde = seguro; amarillo = confirmalo; rojo = sin vincular. '
              '"× unid." son las unidades que trae cada unidad de la columna cantidad (un bulto de 6 = 6).',
              style: textTheme.bodySmall?.copyWith(color: colores.textoTenue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElegirProveedor extends StatelessWidget {
  const _ElegirProveedor({required this.indice, required this.cuit, required this.delCuit, required this.proveedores, required this.onElegir});

  final int indice;
  final String? cuit;
  final List<Proveedor> delCuit;
  final List<Proveedor> proveedores;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cuit == null
                  ? 'No pude leer el CUIT del proveedor. ¿De cuál es esta factura?'
                  : delCuit.length > 1
                  ? 'Este CUIT es de ${delCuit.map((p) => p.nombre).join(' y ')}, y por los productos no me doy cuenta. ¿De cuál es esta factura?'
                  : delCuit.isEmpty
                  ? 'No conozco a este proveedor todavía (CUIT $cuit). ¿De cuál es?'
                  : '¿De cuál proveedor es esta factura?',
              style: textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          DropdownButton<int>(
            key: ValueKey('elegir_proveedor_$indice'),
            hint: const Text('Elegir proveedor'),
            items: [for (final p in proveedores) DropdownMenuItem(value: p.id, child: Text(p.nombre))],
            onChanged: (id) {
              if (id != null) onElegir(id);
            },
          ),
        ],
      ),
    );
  }
}

/// "Reconocí 8 de 10 productos": cuántas líneas ya están seguras (verde), cuántas hay que confirmar (amarillo) y cuántas faltan (rojo).
class _ResumenDeVinculos extends StatelessWidget {
  const _ResumenDeVinculos({required this.propuestas, required this.elegidos});

  final List<PropuestaDeVinculo> propuestas;
  final List<int?> elegidos;

  @override
  Widget build(BuildContext context) {
    final r = resumenDeVinculos(propuestas, elegidos);
    final reconocidas = r[EstadoDeVinculo.seguro]! + r[EstadoDeVinculo.aConfirmar]!;
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: Wrap(
        spacing: Espaciado.sm,
        runSpacing: Espaciado.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Reconocí $reconocidas de ${elegidos.length} productos:', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte)),
          if (r[EstadoDeVinculo.seguro]! > 0) Insignia(texto: '${r[EstadoDeVinculo.seguro]} seguros', tono: Tono.ganancia),
          if (r[EstadoDeVinculo.aConfirmar]! > 0) Insignia(texto: '${r[EstadoDeVinculo.aConfirmar]} para confirmar', tono: Tono.alerta),
          if (r[EstadoDeVinculo.sinVincular]! > 0) Insignia(texto: '${r[EstadoDeVinculo.sinVincular]} sin vincular', tono: Tono.error),
        ],
      ),
    );
  }
}

/// Los títulos de las columnas, con los mismos anchos que cada fila.
class _EncabezadoDeLineas extends StatelessWidget {
  const _EncabezadoDeLineas();

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelMedium?.copyWith(color: context.colores.textoTenue);
    Widget fija(double ancho, String t, {TextAlign alineacion = TextAlign.right}) =>
        SizedBox(width: ancho, child: Text(t, style: estilo, textAlign: alineacion));
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaciado.xs),
      child: Row(
        children: [
          const SizedBox(width: 12 + Espaciado.md),
          Expanded(flex: 3, child: Text('En la factura', style: estilo)),
          const SizedBox(width: Espaciado.md),
          Expanded(flex: 4, child: Text('Tu producto', style: estilo)),
          const SizedBox(width: Espaciado.md),
          fija(_anchoCantidad, 'Cant.'),
          const SizedBox(width: Espaciado.md),
          fija(_anchoMultiplo, '× unid.', alineacion: TextAlign.center),
          const SizedBox(width: Espaciado.md),
          fija(_anchoUnidades, 'Unidades'),
          const SizedBox(width: Espaciado.md),
          fija(_anchoTotal, 'Total'),
          const SizedBox(width: Espaciado.md),
          fija(_anchoCostoUnidad, 'Costo c/u'),
        ],
      ),
    );
  }
}

class _FilaLinea extends StatelessWidget {
  const _FilaLinea({
    super.key,
    required this.descripcion,
    required this.sospechosa,
    required this.propuesta,
    required this.elegido,
    required this.unidades,
    required this.motivoUnidades,
    required this.cantidad,
    required this.version,
    required this.entradas,
    required this.costo,
    required this.onProducto,
    required this.onUnidades,
    this.onCrear,
  });

  final String descripcion;
  final bool sospechosa;
  final PropuestaDeVinculo? propuesta;
  final int? elegido;
  final int unidades;
  final String? motivoUnidades;

  /// Las unidades de la línea tal como las leyó la factura (antes de multiplicar).
  final int cantidad;
  final int version;
  final List<DropdownMenuEntry<int>> entradas;
  final CostoDeLinea costo;
  final ValueChanged<int?> onProducto;
  final ValueChanged<int> onUnidades;
  final VoidCallback? onCrear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final cambiadoAMano = propuesta != null && elegido != propuesta!.productoId;
    final (color, ayuda) = elegido == null
        ? (colores.error, 'Sin vincular: elegí un producto')
        : cambiadoAMano
        ? (acentos.alerta, 'Elegido por vos: tocá "Aprender" para recordarlo')
        : switch (propuesta?.origen) {
            OrigenVinculo.aprendido => (acentos.ganancia, 'Aprendido de facturas anteriores'),
            OrigenVinculo.codigoDeBarras => (acentos.ganancia, 'Por código de barras'),
            OrigenVinculo.ia => (acentos.alerta, 'Lo sugirió la IA: confirmalo'),
            _ => (acentos.alerta, 'Parecido de nombre: confirmalo'),
          };
    final totalUnidades = cantidad * (unidades < 1 ? 1 : unidades);
    final esBulto = unidades > 1;
    // Se pinta de alerta lo que hay que mirar: un bulto propuesto, o una descripción que habla de un pack sin costo con qué comparar.
    final paraMirar = esBulto || (motivoUnidades?.startsWith('La descripción') ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(message: ayuda, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
          const SizedBox(width: Espaciado.md),
          Expanded(
            flex: 3,
            child: Text(
              '${sospechosa ? '⚠ ' : ''}$descripcion',
              style: textTheme.bodyMedium?.copyWith(color: sospechosa ? colores.error : null),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Espaciado.md),
          Expanded(
            flex: 4,
            child: entradas.isEmpty
                ? Text('Sin productos para elegir', style: textTheme.bodySmall)
                : DropdownMenu<int>(
                    key: ValueKey('producto_${version}_$descripcion'),
                    expandedInsets: EdgeInsets.zero,
                    initialSelection: elegido,
                    hintText: 'Elegir producto',
                    enableFilter: true,
                    requestFocusOnTap: true,
                    dropdownMenuEntries: entradas,
                    onSelected: onProducto,
                  ),
          ),
          if (onCrear != null)
            IconButton(key: ValueKey('crear_producto_$descripcion'), tooltip: 'No está en tu lista: crear producto con lo leído', icon: const IconoPlz(IconosPlazoleta.add), onPressed: onCrear),
          const SizedBox(width: Espaciado.md),
          SizedBox(width: _anchoCantidad, child: Text('$cantidad', textAlign: TextAlign.right, style: textTheme.bodyMedium)),
          const SizedBox(width: Espaciado.md),
          SizedBox(
            width: _anchoMultiplo,
            child: Tooltip(
              message: motivoUnidades ?? 'Unidades que trae cada unidad de la columna cantidad (un bulto de 6 = 6). 1 si la factura cuenta unidades sueltas.',
              child: TextFormField(
                key: ValueKey('unidades_${version}_$descripcion'),
                initialValue: '$unidades',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '× ',
                  // La casilla se pinta de alerta cuando hay algo para mirar (ver `paraMirar`).
                  filled: paraMirar,
                  fillColor: paraMirar ? acentos.alertaSuave : null,
                ),
                onChanged: (t) {
                  final n = int.tryParse(t.trim());
                  if (n != null) onUnidades(n);
                },
              ),
            ),
          ),
          const SizedBox(width: Espaciado.md),
          SizedBox(
            width: _anchoUnidades,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$totalUnidades', style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte)),
                if (esBulto) Text('$cantidad bultos × $unidades', style: textTheme.labelSmall?.copyWith(color: acentos.alerta)),
              ],
            ),
          ),
          const SizedBox(width: Espaciado.md),
          SizedBox(width: _anchoTotal, child: Text(formatearARS(costo.totalCentavos), textAlign: TextAlign.right, style: textTheme.bodyMedium)),
          const SizedBox(width: Espaciado.md),
          SizedBox(
            width: _anchoCostoUnidad,
            child: Text(
              '${formatearARS(costo.costoUnitarioCentavos)} c/u',
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte),
            ),
          ),
        ],
      ),
    );
  }
}
