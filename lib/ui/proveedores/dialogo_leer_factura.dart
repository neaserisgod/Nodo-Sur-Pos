// "Leer una factura (prueba)" (El dueño, 2026-10-05): elegís fotos o PDF de facturas de compra, la IA las transcribe y ves el costo real
// de cada producto, si la factura cierra con su total y con qué producto de tu base se vincula cada línea. TODAVÍA NO TOCA costos, stock ni
// deuda: lo único que guarda es lo que "aprende" (vínculos y CUIT del proveedor), para que la próxima factura salga vinculada sola.
// "Copiar lectura" deja el JSON de la IA en el portapapeles. Plan en `docs/PLAN-FACTURAS.md`.

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
import '../tema/tokens.dart';

/// [clienteIa] y [adjuntosIniciales] son solo para tests: el selector de archivos es nativo y no se puede manejar desde un test.
Future<void> mostrarDialogoLeerFactura(
  BuildContext context, {
  required AppDatabase db,
  http.Client? clienteIa,
  List<AdjuntoGemini> adjuntosIniciales = const [],
}) {
  return mostrarModal<void>(context, builder: (_) => _DialogoLeerFactura(db: db, clienteIa: clienteIa, adjuntosIniciales: adjuntosIniciales));
}

/// Todo lo de una factura leída: el proveedor, la propuesta de vínculos y lo que el dueño fue eligiendo.
class _EstadoFactura {
  _EstadoFactura(this.n);

  final FacturaNormalizada n;
  Proveedor? proveedor;
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
  const _DialogoLeerFactura({required this.db, this.clienteIa, this.adjuntosIniciales = const []});

  final AppDatabase db;
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
        e.proveedor = await proveedorPorCuit(widget.db, e.n.leida.proveedorCuit);
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
    await asociarCuit(widget.db, proveedorId: proveedor.id, cuit: e.n.leida.proveedorCuit);
    e.proveedor = proveedor;
    await _proponer(e, conIa: true);
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lectura copiada al portapapeles')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    return Modal(
      titulo: 'Leer una factura (prueba)',
      subtitulo: 'Elegí fotos o PDF. La IA las lee y la vinculás con tus productos. Todavía no toca costos, stock ni deuda.',
      ancho: 1000,
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!ClaveGemini.configurada)
                Text('Falta la clave de la IA: cargala en Configuración › Asistente IA.', style: textTheme.bodyMedium?.copyWith(color: colores.error)),
              // Mientras se prueba, el modelo se cambia acá mismo: es el mismo ajuste que en Configuración › Asistente IA.
              if (ClaveGemini.configurada) Padding(padding: const EdgeInsets.only(bottom: Espaciado.sm), child: SelectorModeloIa(onCambio: () => setState(() {}))),
              if (_nombres.isEmpty && ClaveGemini.configurada)
                Text('Todavía no elegiste nada.', style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
              for (final n in _nombres) Text(n, style: textTheme.bodySmall),
              if (_leyendo) const Padding(padding: EdgeInsets.only(top: Espaciado.md), child: LinearProgressIndicator()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.md),
                  child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: colores.error)),
                ),
              if (_resultado != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.md),
                  child: Text('Leído con ${_resultado!.modelo}', style: textTheme.bodySmall?.copyWith(color: colores.textoTenue)),
                ),
                for (final a in _resultado!.lectura.advertencias) Text(a, style: textTheme.bodySmall),
                // El Modal admite 3 botones como máximo: esta acción va acá y no abajo.
                Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _copiar, child: const Text('Copiar lectura'))),
                for (var i = 0; i < _facturas.length; i++)
                  _TarjetaFactura(
                    indice: i,
                    e: _facturas[i],
                    proveedores: _proveedores,
                    nombresDeProductos: {for (final c in _catalogo) c.id: c.nombre},
                    onProveedor: (id) => _elegirProveedor(_facturas[i], id),
                    onProducto: (linea, id) => setState(() {
                      _facturas[i].producto[linea] = id;
                      // Otro producto, otro costo para comparar: se vuelve a proponer el bulto de esa línea.
                      _sugerirUnidades(_facturas[i], lineas: {linea});
                      _facturas[i].version++;
                    }),
                    onUnidades: (linea, n) => setState(() => _facturas[i].multiplicador[linea] = n < 1 ? 1 : n),
                    onAprender: () => _aprender(_facturas[i]),
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

class _TarjetaFactura extends StatelessWidget {
  const _TarjetaFactura({
    required this.indice,
    required this.e,
    required this.proveedores,
    required this.nombresDeProductos,
    required this.onProveedor,
    required this.onProducto,
    required this.onUnidades,
    required this.onAprender,
  });

  final int indice;
  final _EstadoFactura e;
  final List<Proveedor> proveedores;
  final Map<int, String> nombresDeProductos;
  final ValueChanged<int> onProveedor;
  final void Function(int linea, int? productoId) onProducto;
  final void Function(int linea, int unidades) onUnidades;
  final VoidCallback onAprender;

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
    final cabecera = [
      if (f.proveedorNombre != null) f.proveedorNombre!,
      if (f.tipo != null) 'Factura ${f.tipo}',
      if (f.numero != null) f.numero!,
      if (f.fecha != null) '${f.fecha!.day}/${f.fecha!.month}/${f.fecha!.year}',
      if (f.condicionPago != null) f.condicionPago == 'contado' ? 'contado' : 'cuenta corriente',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.lg),
      child: Container(
        padding: const EdgeInsets.all(Espaciado.md),
        decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(Bento.radio)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cabecera.isEmpty ? 'Factura' : cabecera, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte)),
            const SizedBox(height: Espaciado.xs),
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
            if (e.proveedor == null) _ElegirProveedor(indice: indice, cuit: f.proveedorCuit, proveedores: proveedores, onElegir: onProveedor),
            if (e.consultandoIa)
              Padding(
                padding: const EdgeInsets.only(top: Espaciado.sm),
                child: Text('La IA está ayudando a vincular lo que falta…', style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario)),
              ),
            if (e.avisoIa != null) Padding(padding: const EdgeInsets.only(top: Espaciado.xs), child: Text(e.avisoIa!, style: textTheme.bodySmall)),
            const SizedBox(height: Espaciado.sm),
            if (costos == null)
              Text('No se pudieron calcular los costos: revisá los importes de la factura.', style: textTheme.bodySmall?.copyWith(color: colores.error))
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
                ),
            const SizedBox(height: Espaciado.sm),
            Row(
              children: [
                TextButton(
                  key: ValueKey('aprender_$indice'),
                  onPressed: e.proveedor != null && e.vinculadas > 0 ? onAprender : null,
                  child: Text('Aprender estos vínculos (${e.vinculadas})'),
                ),
                if (e.avisoAprendido != null) Expanded(child: Text(e.avisoAprendido!, style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario))),
              ],
            ),
            Text(
              [
                if (f.pie.descuentoGlobalCentavos > 0) 'Descuento ${formatearARS(f.pie.descuentoGlobalCentavos)}',
                if (f.pie.percepcionesCentavos > 0) 'Percepciones ${formatearARS(f.pie.percepcionesCentavos)}',
                if (f.pie.internosCentavos > 0) 'Impuestos internos ${formatearARS(f.pie.internosCentavos)}',
                if (control != null) 'Total calculado ${formatearARS(control.totalCalculadoCentavos)}',
                if (f.pie.totalCentavos != null) 'impreso ${formatearARS(f.pie.totalCentavos!)}',
              ].join(' · '),
              style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
            ),
            Text(
              'El costo por unidad incluye IVA e impuestos y lo repartido del pie. Verde = ya aprendido; amarillo = una propuesta que tenés que confirmar; rojo = sin vincular. '
              '"× unidades" son las unidades que trae cada unidad de la columna cantidad (un bulto de 6 = 6).',
              style: textTheme.bodySmall?.copyWith(color: colores.textoTenue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ElegirProveedor extends StatelessWidget {
  const _ElegirProveedor({required this.indice, required this.cuit, required this.proveedores, required this.onElegir});

  final int indice;
  final String? cuit;
  final List<Proveedor> proveedores;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cuit == null ? 'No pude leer el CUIT del proveedor. ¿De cuál es esta factura?' : 'No conozco a este proveedor todavía (CUIT $cuit). ¿De cuál es?',
              style: textTheme.bodySmall,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(message: ayuda, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              '${sospechosa ? '⚠ ' : ''}$descripcion',
              style: textTheme.bodySmall?.copyWith(color: sospechosa ? colores.error : null),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          SizedBox(
            width: 290,
            child: entradas.isEmpty
                ? Text('Sin productos para elegir', style: textTheme.bodySmall)
                : DropdownMenu<int>(
                    key: ValueKey('producto_${version}_$descripcion'),
                    width: 290,
                    initialSelection: elegido,
                    hintText: 'Elegir producto',
                    enableFilter: true,
                    requestFocusOnTap: true,
                    dropdownMenuEntries: entradas,
                    onSelected: onProducto,
                  ),
          ),
          const SizedBox(width: Espaciado.sm),
          SizedBox(
            width: 70,
            child: Tooltip(
              message: motivoUnidades ?? 'Unidades que trae cada unidad de la columna cantidad (un bulto de 6 = 6). 1 si la factura cuenta unidades sueltas.',
              child: TextFormField(
                key: ValueKey('unidades_${version}_$descripcion'),
                initialValue: '$unidades',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: unidades > 1 ? 'bulto ×' : '× unid.',
                  isDense: true,
                  // Un punto de color: hay algo para confirmar en bultos de esta línea.
                  suffixIcon: motivoUnidades != null ? const Icon(Icons.info_outline, size: 14) : null,
                ),
                onChanged: (t) {
                  final n = int.tryParse(t.trim());
                  if (n != null) onUnidades(n);
                },
              ),
            ),
          ),
          SizedBox(width: 56, child: Text('× ${cantidad * (unidades < 1 ? 1 : unidades)}', textAlign: TextAlign.right, style: textTheme.bodySmall)),
          SizedBox(width: 100, child: Text(formatearARS(costo.totalCentavos), textAlign: TextAlign.right, style: textTheme.bodySmall)),
          SizedBox(
            width: 110,
            child: Text(
              '${formatearARS(costo.costoUnitarioCentavos)} c/u',
              textAlign: TextAlign.right,
              style: textTheme.bodySmall?.copyWith(fontWeight: Pesos.fuerte),
            ),
          ),
        ],
      ),
    );
  }
}
