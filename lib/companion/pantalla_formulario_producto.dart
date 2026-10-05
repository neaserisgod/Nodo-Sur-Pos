// Nuevo / Editar producto, tal cual el mock (docs/03 D6): una página con
// DATOS BÁSICOS (nombre, código de barras, por peso, precio, costo, stock) y
// ORGANIZACIÓN (categoría, proveedor, activo), con "Guardar producto" abajo.
//
// Lo que ya hacía la app y se conserva: el margen en vivo ("Ganás $ X · N %"),
// poder tipear el stock al editar (deja su rastro de movimiento) y confirmar
// antes de perder lo cargado.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/dinero.dart';
import '../domain/ganancia.dart';
import 'cliente_companion.dart';
import 'escanear_codigo.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'servicio_companion.dart';

/// Abre la página de alta o edición. Devuelve `true` si se guardó algo.
Future<bool> mostrarFormularioProducto(
  BuildContext context, {
  required ServicioCompanion cliente,
  required int usuarioId,
  required List<ProveedorCompanion> proveedores,
  required List<CategoriaCompanion> categorias,
  ProductoCompanion? producto,
  String? codigoInicial,
}) async {
  final guardado = await pushSinTeclado<bool>(
    context,
    (_) => PantallaFormularioProducto(cliente: cliente, usuarioId: usuarioId, proveedores: proveedores, categorias: categorias, producto: producto, codigoInicial: codigoInicial),
  );
  return guardado ?? false;
}

class PantallaFormularioProducto extends StatefulWidget {
  const PantallaFormularioProducto({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.proveedores,
    required this.categorias,
    this.producto,
    this.codigoInicial,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;

  /// Null = alta de un producto nuevo.
  final ProductoCompanion? producto;

  /// Código ya leído (al escanear algo que no existe): arranca cargado.
  final String? codigoInicial;

  @override
  State<PantallaFormularioProducto> createState() => _PantallaFormularioProductoState();
}

class _PantallaFormularioProductoState extends State<PantallaFormularioProducto> {
  static final _soloNumeros = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

  late final _nombre = TextEditingController(text: widget.producto?.nombre ?? '');
  late final _codigo = TextEditingController(text: widget.producto?.codigoBarras ?? widget.codigoInicial ?? '');
  late final _precio = TextEditingController(text: _texto(widget.producto == null ? null : (widget.producto!.esPesable ? widget.producto!.precioPorKiloCentavos : widget.producto!.precioCentavos)));
  late final _costo = TextEditingController(text: _texto(widget.producto == null ? null : (widget.producto!.esPesable ? widget.producto!.costoPorKiloCentavos : widget.producto!.costoCentavos)));
  late final _stock = TextEditingController(text: widget.producto == null ? '' : '${widget.producto!.esPesable ? widget.producto!.stockGramos ?? 0 : widget.producto!.stock}');

  late bool _esPesable = widget.producto?.esPesable ?? false;
  late bool _activo = widget.producto?.activo ?? true;
  int? _proveedorId;
  int? _categoriaId;
  bool _guardando = false;
  bool _sucio = false;
  String? _error;

  static String _texto(int? centavos) => centavos == null || centavos == 0 ? '' : formatearARS(centavos, conSigno: false);

  @override
  void initState() {
    super.initState();
    _proveedorId = widget.producto?.proveedorId;
    _categoriaId = widget.producto?.categoriaId;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _precio.dispose();
    _costo.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _cambio() => setState(() => _sucio = true);

  /// El precio que da [g] % de ganancia sobre el costo cargado (una sola cuenta: `domain/ganancia.dart`, Regla 3).
  int _precioConGanancia(int g) => precioDesdeCostoYGanancia(_plata(_costo) ?? 0, g * 100);

  int? _plata(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    try {
      return parsearARS(t);
    } on FormatException {
      return null;
    }
  }

  /// "Ganás $ X por unidad · N %" o el aviso de que el precio no cubre el costo.
  ({String texto, bool cubre})? get _margen {
    final precio = _plata(_precio);
    final costo = _plata(_costo);
    if (precio == null || costo == null || costo <= 0) return null;
    if (precio <= costo) return (texto: 'El precio no cubre el costo', cubre: false);
    try {
      final bp = gananciaBpDesdeCostoYPrecio(costo, precio);
      return (texto: 'Ganás ${plataNs(precio - costo)} ${_esPesable ? 'por kilo' : 'por unidad'} · ${(bp / 100).round()}%', cubre: true);
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _escanear() async {
    final c = await escanearCodigo(context);
    if (c == null || !mounted) return;
    setState(() {
      _codigo.text = c;
      _sucio = true;
    });
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      mostrarAvisoNs(context, 'Falta el nombre');
      return;
    }
    final precioTexto = _precio.text.trim();
    if (precioTexto.isEmpty) {
      mostrarAvisoNs(context, _esPesable ? 'Un producto por peso necesita precio por kilo' : 'Falta el precio');
      return;
    }
    final int? precio;
    final int? costo;
    final int? stockTipeado;
    try {
      precio = parsearARS(precioTexto);
      costo = _costo.text.trim().isEmpty ? null : parsearARS(_costo.text);
      stockTipeado = _stock.text.trim().isEmpty ? null : int.parse(_stock.text.trim());
    } on FormatException {
      setState(() => _error = 'Precio, costo o stock inválido');
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final navegador = Navigator.of(context);
    final esAlta = widget.producto == null;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final codigo = _codigo.text.trim().isEmpty ? null : _codigo.text.trim();
      if (esAlta) {
        await widget.cliente.crearProducto(
          nombre: _nombre.text.trim(),
          codigoBarras: codigo,
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          precioCentavos: _esPesable ? null : precio,
          costoCentavos: _esPesable ? null : costo,
          precioPorKiloCentavos: _esPesable ? precio : null,
          costoPorKiloCentavos: _esPesable ? costo : null,
          stock: _esPesable ? 0 : (stockTipeado ?? 0),
          stockGramos: _esPesable ? stockTipeado : null,
          usuarioId: widget.usuarioId,
        );
      } else {
        final p = widget.producto!;
        await widget.cliente.actualizarProducto(
          p.id,
          nombre: _nombre.text.trim(),
          codigoBarras: codigo,
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          precioCentavos: _esPesable ? null : precio,
          costoCentavos: _esPesable ? null : costo,
          precioPorKiloCentavos: _esPesable ? precio : null,
          costoPorKiloCentavos: _esPesable ? costo : null,
          stock: p.stock,
          stockGramos: p.stockGramos,
          activo: _activo,
          usuarioId: widget.usuarioId,
        );
        final actual = _esPesable ? p.stockGramos ?? 0 : p.stock;
        if (stockTipeado != null && stockTipeado != actual) {
          await widget.cliente.ajustarStock(p.id, stock: _esPesable ? p.stock : stockTipeado, stockGramos: _esPesable ? stockTipeado : null, motivo: 'Editado desde ficha de producto', usuarioId: widget.usuarioId);
        }
      }
      _sucio = false;
      if (!mounted) return;
      navegador.pop(true);
      mostrarAvisoEnNs(overlay, esAlta ? 'Producto guardado' : 'Cambios guardados');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _volver() async {
    if (!_sucio || await confirmarSalirSinGuardar(context, texto: 'Lo que cargaste todavía no se guardó — se pierde si salís ahora.', seguir: 'Seguir acá')) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final esAlta = widget.producto == null;
    final margen = _margen;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _volver();
      },
      child: Scaffold(
        backgroundColor: ns.paper,
        body: SafeArea(
          child: PantallaEntradaNs(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CabeceraSubNs(titulo: esAlta ? 'Nuevo producto' : 'Editar producto', tamanio: 32, onVolver: _volver),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        const SeccionNs('Datos básicos'),
                        const SizedBox(height: 10),
                        CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej: Alfajor triple', onChanged: (_) => _cambio()),
                        const SizedBox(height: 10),
                        CampoNs(etiqueta: 'Código de barras (opcional)', controller: _codigo, placeholder: 'Escribilo o escaneá', teclado: TextInputType.number, onChanged: (_) => _cambio()),
                        const SizedBox(height: 10),
                        BotonNs.secundario(context, 'Escanear código', _escanear, alto: 54, icono: IconoNs.escanear),
                        const SizedBox(height: 10),
                        InterruptorNs(
                          etiqueta: 'Se vende por peso',
                          descripcion: _esPesable ? 'El precio y el stock van por kilo y gramos' : 'Se vende por unidad',
                          encendido: _esPesable,
                          onCambio: (v) => setState(() {
                            _esPesable = v;
                            _sucio = true;
                          }),
                        ),
                        const SizedBox(height: 10),
                        CampoNs(etiqueta: _esPesable ? 'Precio por kilo' : 'Precio de venta', controller: _precio, grande: true, placeholder: '\$ 0', teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _soloNumeros, onChanged: (_) => _cambio()),
                        const SizedBox(height: 10),
                        CampoNs(etiqueta: _esPesable ? 'Lo que te cuesta el kilo' : 'Lo que te cuesta', controller: _costo, placeholder: '\$ 0', teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _soloNumeros, onChanged: (_) => _cambio()),
                        if (margen != null) ...[const SizedBox(height: 10), InfoNs(margen.texto, tono: margen.cubre ? TonoNs.good : TonoNs.bad)],
                        if ((_plata(_costo) ?? 0) > 0) ...[
                          const SizedBox(height: 10),
                          Text('Poner el precio con ganancia', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final g in const [20, 30, 40])
                                ChipNs(
                                  texto: '$g% ganancia',
                                  activo: _plata(_precio) == _precioConGanancia(g),
                                  onTap: () => setState(() {
                                    _precio.text = '${_precioConGanancia(g) ~/ centavosPorPeso}';
                                    _sucio = true;
                                  }),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        CampoNs(etiqueta: _esPesable ? 'Cuántos gramos tenés ahora' : 'Cuántas unidades tenés ahora', controller: _stock, placeholder: '0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _cambio()),
                        const SizedBox(height: 22),
                        const SeccionNs('Organización'),
                        const SizedBox(height: 10),
                        _FilaOpciones(
                          etiqueta: 'Categoría',
                          opciones: [('Sin categoría', null), for (final c in widget.categorias) (c.nombre, c.id)],
                          elegida: _categoriaId,
                          onElegir: (v) => setState(() {
                            _categoriaId = v;
                            _sucio = true;
                          }),
                        ),
                        const SizedBox(height: 14),
                        _FilaOpciones(
                          etiqueta: 'Proveedor',
                          opciones: [('Sin proveedor', null), for (final p in widget.proveedores) (p.nombre, p.id)],
                          elegida: _proveedorId,
                          onElegir: (v) => setState(() {
                            _proveedorId = v;
                            _sucio = true;
                          }),
                        ),
                        const SizedBox(height: 14),
                        InterruptorNs(
                          etiqueta: 'Activo',
                          descripcion: _activo ? 'Aparece en la venta' : 'Oculto en la venta',
                          encendido: _activo,
                          onCambio: (v) => setState(() {
                            _activo = v;
                            _sucio = true;
                          }),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[const SizedBox(height: 14), InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo, tamanio: 15, peso: FontWeight.w500)],
                  const SizedBox(height: 14),
                  BotonNs.primario(context, _guardando ? 'Guardando…' : (esAlta ? 'Dar de alta' : 'Guardar cambios'), _guardando ? null : _guardar, habilitado: !_guardando),
                  const SizedBox(height: 8),
                  BotonNs.secundario(context, 'Cancelar', _guardando ? null : _volver),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila de opciones con su etiqueta (chips que saltan de línea).
class _FilaOpciones extends StatelessWidget {
  const _FilaOpciones({required this.etiqueta, required this.opciones, required this.elegida, required this.onElegir});
  final String etiqueta;
  final List<(String, int?)> opciones;
  final int? elegida;
  final ValueChanged<int?> onElegir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: estiloNs(14, peso: FontWeight.w600, color: context.ns.mute)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final o in opciones) ChipNs(texto: o.$1, activo: elegida == o.$2, onTap: () => onElegir(o.$2))]),
      ],
    );
  }
}
