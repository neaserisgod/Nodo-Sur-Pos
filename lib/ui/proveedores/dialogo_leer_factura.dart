// "Leer una factura" (El dueño, 2026-10-05): elegís fotos o PDF de facturas de compra, la IA las transcribe y ves el costo real de cada
// producto, si la factura cierra con su total y con qué producto de tu base se vincula cada línea (lo que falta se crea desde la línea).
// "Aplicar factura" (2026-10-07) suma el stock, pone el costo y carga la deuda en la cuenta corriente, con "Deshacer"
// (`data/repositorio_facturas_compra.dart`). Lo que se confirma se aprende (vínculos y CUIT del proveedor), para que la próxima factura
// salga vinculada sola. "Copiar lectura" deja el JSON de la IA en el portapapeles. Plan en `docs/PLAN-FACTURAS.md`.

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../comun/aviso_superior.dart';
import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/factura_compra.dart';
import '../../domain/lectura_factura.dart';
import '../../servicios/gemini.dart';
import '../../servicios/flujo_factura.dart';
import '../../domain/vinculo_factura.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../configuracion/seccion_asistente_ia.dart' show SelectorModeloIa;
import '../tema/acentos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../tema/iconos.dart';
import 'dialogo_cuenta_corriente.dart';
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

/// Los productos para elegir en una línea, como entradas del selector.
extension on EstadoFactura {
  List<DropdownMenuEntry<int>> get entradas => [for (final c in candidatos) DropdownMenuEntry<int>(value: c.id, label: c.nombre)];
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

/// Solo dibuja: lo que hace cada botón vive en [FlujoFactura] (`servicios/flujo_factura.dart`), el mismo que usa el celular.
class _DialogoLeerFacturaState extends State<_DialogoLeerFactura> {
  late final FlujoFactura _flujo = FlujoFactura(db: widget.db, clienteIa: widget.clienteIa, adjuntosIniciales: widget.adjuntosIniciales)
    ..addListener(_redibujar);

  void _redibujar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flujo.dispose();
    super.dispose();
  }

  Future<void> _elegir() async {
    final archivos = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Fotos y PDF', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf']),
      ],
    );
    await _flujo.elegirArchivos([for (final f in archivos) (nombre: f.name, bytes: await f.readAsBytes())]);
  }

  Future<void> _aplicarFactura(EstadoFactura e) async {
    final controlador = widget.controlador;
    if (controlador == null) return;
    final control = e.n.control;
    if (control != null && e.hayQueConfirmar && _flujo.lineasParaAplicar(e) != null) {
      final seguir = await mostrarModal<bool>(
        context,
        builder: (ctx) => Modal(
          titulo: 'La factura no cierra',
          contenido: Text(
            'Lo leído tiene ${formatearARS(control.diferenciaCentavos.abs())} de diferencia con el total impreso: puede haber algo mal leído. '
            'Si aplicás igual, la deuda se carga por el total impreso.',
          ),
          botones: [
            BotonSecundario(texto: 'Revisar', onPressed: () => Navigator.of(ctx).pop(false)),
            BotonPrimario(texto: 'Aplicar igual', onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
    final aplicada = await _flujo.aplicar(e, usuarioId: controlador.usuarioId);
    if (!aplicada) return;
    await controlador.recargarSeleccionActual();
    if (!mounted) return;
    mostrarAviso(context, 'Factura aplicada', textoAccion: 'Deshacer', alAccionar: () => _deshacerFactura(e));
  }

  Future<void> _deshacerFactura(EstadoFactura e) async {
    final controlador = widget.controlador;
    if (controlador == null) return;
    final aviso = await _flujo.deshacer(e, usuarioId: controlador.usuarioId);
    if (aviso == null) return;
    await controlador.recargarSeleccionActual();
    if (mounted) mostrarAviso(context, aviso);
  }

  /// Contado: el pago va por el camino de siempre (la cuenta corriente), con la deuda recién cargada.
  Future<void> _pagarAhora(EstadoFactura e) async {
    final controlador = widget.controlador;
    final proveedor = e.proveedor;
    if (controlador == null || proveedor == null) return;
    await mostrarDialogoCuentaCorriente(context, db: widget.db, proveedor: proveedor, usuarioId: controlador.usuarioId, sesionCajaId: controlador.sesionCajaId);
    await controlador.recargarSeleccionActual();
  }

  /// Una línea que no está en el catálogo (o que el parecido vinculó con otro producto parecido, "XB BOX" con "XB convertible BOX"): se da de
  /// alta con el formulario de siempre, precargado con lo leído — nombre, costo por unidad, proveedor y código de barras si viene —, y la
  /// línea queda vinculada al producto nuevo.
  Future<void> _crearProducto(EstadoFactura e, int linea) async {
    final controlador = widget.controlador;
    if (controlador == null) return;
    final datos = _flujo.datosParaCrear(e, linea);
    final id = await mostrarDialogoEditarProducto(
      context,
      controlador: controlador,
      proveedorIdPreseleccionado: e.proveedor?.id,
      inicial: DatosProductoNuevo(
        nombre: datos.nombre,
        codigoBarras: datos.codigoBarras,
        costoCentavos: datos.costoCentavos,
        mejorarNombre: _flujo.mejorarNombre(e, linea),
      ),
    );
    if (id == null || !mounted) return;
    await _flujo.productoCreado(e, linea, id);
  }

  Future<void> _copiar() async {
    final texto = _flujo.lecturaEnJson;
    if (texto == null) return;
    await Clipboard.setData(ClipboardData(text: texto));
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
      subtitulo: 'Elegí fotos o PDF. La IA las lee, las vinculás con tus productos y las aplicás: stock, costo y deuda.',
      ancho: 1180,
      contenido: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: alto),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BarraDeLectura(
                nombres: _flujo.nombres,
                leyendo: _flujo.leyendo,
                error: _flujo.error,
                onCambioModelo: () => setState(() {}),
              ),
              if (_flujo.resultado != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.lg),
                  child: Row(
                    children: [
                      Expanded(child: Text('Leído con ${_flujo.resultado!.modelo}', style: textTheme.bodySmall?.copyWith(color: colores.textoTenue))),
                      // El Modal admite 3 botones como máximo: esta acción va acá y no abajo.
                      TextButton(onPressed: _copiar, child: const Text('Copiar lectura')),
                    ],
                  ),
                ),
                for (final a in _flujo.resultado!.lectura.advertencias) Text(a, style: textTheme.bodySmall),
                for (final (i, e) in _flujo.facturas.indexed)
                  _TarjetaFactura(
                    indice: i,
                    e: e,
                    proveedores: _flujo.proveedores,
                    nombresDeProductos: {for (final c in _flujo.catalogo) c.id: c.nombre},
                    onProveedor: (id) => _flujo.elegirProveedor(e, id),
                    onCambiarProveedor: () => _flujo.cambiarProveedor(e),
                    onProducto: (linea, id) => _flujo.elegirProducto(e, linea, id),
                    onUnidades: (linea, n) => _flujo.cambiarUnidades(e, linea, n),
                    onNoVa: (linea, v) => _flujo.marcarNoVa(e, linea, v),
                    onSumarStock: (v) => _flujo.sumarStock(e, v),
                    onAplicarFactura: widget.controlador == null ? null : () => _aplicarFactura(e),
                    onDeshacerFactura: () => _deshacerFactura(e),
                    onPagarAhora: () => _pagarAhora(e),
                    onAprender: () => _flujo.aprender(e),
                    onCrearProducto: widget.controlador == null ? null : (linea) => _crearProducto(e, linea),
                  ),
              ],
            ],
          ),
        ),
      ),
      botones: [
        BotonSecundario(texto: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        BotonSecundario(texto: 'Elegir archivos', onPressed: _flujo.leyendo ? null : _elegir),
        BotonPrimario(
          texto: _flujo.leyendo ? 'Leyendo…' : 'Leer con IA',
          onPressed: _flujo.puedeLeer ? _flujo.leer : null,
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
const double _anchoNoVa = 56;

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
    required this.onNoVa,
    required this.onSumarStock,
    required this.onDeshacerFactura,
    required this.onPagarAhora,
    this.onCrearProducto,
    this.onAplicarFactura,
  });

  final int indice;
  final EstadoFactura e;
  final List<Proveedor> proveedores;
  final Map<int, String> nombresDeProductos;
  final ValueChanged<int> onProveedor;
  final VoidCallback onCambiarProveedor;
  final void Function(int linea, int? productoId) onProducto;
  final void Function(int linea, int unidades) onUnidades;
  final VoidCallback onAprender;
  final ValueChanged<int>? onCrearProducto;
  final void Function(int linea, bool noVa) onNoVa;
  final ValueChanged<bool> onSumarStock;

  /// Null sin el controlador de Proveedores (no hay usuario con quien aplicar): solo se revisa.
  final VoidCallback? onAplicarFactura;
  final VoidCallback onDeshacerFactura;
  final VoidCallback onPagarAhora;

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
                        noVa: i < e.noVa.length && e.noVa[i],
                        onNoVa: (v) => onNoVa(i, v),
                        avisoPrecio: e.avisosPrecio[i],
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
            if (onAplicarFactura != null) ...[
              const SizedBox(height: Espaciado.md),
              _BarraAplicar(indice: indice, e: e, onSumarStock: onSumarStock, onAplicar: onAplicarFactura!, onDeshacer: onDeshacerFactura, onPagarAhora: onPagarAhora),
            ],
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
          fija(_anchoNoVa, 'No va', alineacion: TextAlign.center),
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
    required this.noVa,
    required this.onNoVa,
    this.avisoPrecio,
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
  final bool noVa;
  final ValueChanged<bool> onNoVa;
  final String? avisoPrecio;

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
    final fila = Row(
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
          SizedBox(
            width: _anchoNoVa,
            child: Tooltip(
              message: 'No va: no es del local. Entra en la deuda, pero no suma stock ni cambia el costo.',
              child: Checkbox(key: ValueKey('no_va_$descripcion'), value: noVa, onChanged: (v) => onNoVa(v ?? false)),
            ),
          ),
        ],
      );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
      child: Opacity(
        opacity: noVa ? 0.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            fila,
            if (avisoPrecio != null && !noVa)
              Padding(
                padding: const EdgeInsets.only(left: 12 + Espaciado.md, top: Espaciado.xs),
                child: Text(avisoPrecio!, style: textTheme.bodySmall?.copyWith(color: colores.error)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Abajo de cada factura: sumar al stock, aplicar, y lo aplicado (con Deshacer y, si fue de contado, Pagar ahora).
class _BarraAplicar extends StatelessWidget {
  const _BarraAplicar({required this.indice, required this.e, required this.onSumarStock, required this.onAplicar, required this.onDeshacer, required this.onPagarAhora});

  final int indice;
  final EstadoFactura e;
  final ValueChanged<bool> onSumarStock;
  final VoidCallback onAplicar;
  final VoidCallback onDeshacer;
  final VoidCallback onPagarAhora;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final aplicada = e.facturaAplicadaId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!aplicada) ...[
              Checkbox(key: ValueKey('sumar_stock_$indice'), value: e.sumarStock, onChanged: (v) => onSumarStock(v ?? true)),
              const Text('Sumar al stock'),
              const Spacer(),
              ElevatedButton(
                key: ValueKey('aplicar_factura_$indice'),
                onPressed: e.aplicando ? null : onAplicar,
                child: Text(e.aplicando ? 'Aplicando…' : 'Aplicar factura'),
              ),
            ] else ...[
              Expanded(child: Text(e.resumenAplicada ?? 'Aplicada', style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium))),
              if (e.n.leida.condicionPago == 'contado')
                TextButton(key: ValueKey('pagar_ahora_$indice'), onPressed: onPagarAhora, child: const Text('Pagar ahora')),
              TextButton(key: ValueKey('deshacer_factura_$indice'), onPressed: onDeshacer, child: const Text('Deshacer')),
            ],
          ],
        ),
        if (e.errorAplicar != null) Text(e.errorAplicar!, style: textTheme.bodySmall?.copyWith(color: colores.error)),
      ],
    );
  }
}
