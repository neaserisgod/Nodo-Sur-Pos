// Hoja "Editar en lote" (docs/03 H5): elegir qué hacer con los productos
// marcados (subir precios, cargar un pedido, cambiar proveedor — y, como ya hacía
// la app, subir costos y cambiar categoría), pasar por la revisión "Vas a aplicar
// esto" y aplicar. Con más de 50 % de aumento avisa que puede haber un dígito de más.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../domain/edicion_masiva_precios.dart';
import '../../domain/edicion_masiva_stock.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

/// `true` si se aplicó el cambio.
Future<bool> mostrarHojaLote(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
  required List<ProductoCompanion> productos,
  required List<ProveedorCompanion> proveedores,
  required List<CategoriaCompanion> categorias,
}) async {
  final r = await mostrarHojaNs<bool>(context, builder: (_) => _HojaLote(servicio: servicio, usuarioId: usuarioId, productos: productos, proveedores: proveedores, categorias: categorias));
  return r ?? false;
}

enum _Op { precios, costos, pedido, proveedor, categoria }

class _HojaLote extends StatefulWidget {
  const _HojaLote({required this.servicio, required this.usuarioId, required this.productos, required this.proveedores, required this.categorias});
  final ServicioCompanion servicio;
  final int usuarioId;
  final List<ProductoCompanion> productos;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;

  @override
  State<_HojaLote> createState() => _HojaLoteState();
}

class _HojaLoteState extends State<_HojaLote> {
  _Op _op = _Op.precios;
  bool _porcentaje = true;
  int? _proveedor;
  int? _categoria;
  final _valor = TextEditingController();
  bool _revisando = false;
  bool _aplicando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _proveedor = widget.proveedores.firstOrNull?.id;
    _categoria = widget.categorias.firstOrNull?.id;
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  bool get _esMonto => _op == _Op.precios || _op == _Op.costos;
  double get _numero => double.tryParse(_valor.text.trim().replaceAll(',', '.')) ?? 0;
  bool get _listo => switch (_op) {
    _Op.proveedor => _proveedor != null,
    _Op.categoria => _categoria != null,
    _ => _numero > 0,
  };

  /// Texto de lo que se va a hacer (docs/03 H5).
  String get _resumen {
    final v = _valor.text.trim();
    return switch (_op) {
      _Op.precios => _porcentaje ? 'Sumar $v % al precio de venta' : 'Sumar ${plataNs(_numero.round() * centavosPorPeso)} al precio de venta',
      _Op.costos => _porcentaje ? 'Sumar $v % al costo' : 'Sumar ${plataNs(_numero.round() * centavosPorPeso)} al costo',
      _Op.pedido => 'Sumar ${_numero.round()} unidades al stock',
      _Op.proveedor => 'Asignar el proveedor ${widget.proveedores.firstWhere((p) => p.id == _proveedor).nombre}',
      _Op.categoria => 'Asignar la categoría ${widget.categorias.firstWhere((c) => c.id == _categoria).nombre}',
    };
  }

  String? get _ejemplo {
    if (!_esMonto || _numero <= 0 || widget.productos.isEmpty) return null;
    final p = widget.productos.first;
    final actual = _op == _Op.precios ? (p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos) : (p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos);
    if (actual == null) return null;
    final nuevo = _porcentaje ? ((actual * (1 + _numero / 100)) / centavosPorPeso).round() * centavosPorPeso : actual + _numero.round() * centavosPorPeso;
    return 'Por ejemplo: ${p.nombre} pasaría de ${plataNs(actual)} a ${plataNs(nuevo)}';
  }

  Future<void> _aplicar() async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final navegador = Navigator.of(context);
    final ids = [for (final p in widget.productos) p.id];
    setState(() {
      _aplicando = true;
      _error = null;
    });
    try {
      switch (_op) {
        case _Op.precios:
        case _Op.costos:
          await widget.servicio.ajustarMontoEnLote(
            productoIds: ids,
            campo: _op == _Op.precios ? CampoMonto.precio : CampoMonto.costo,
            tipo: _porcentaje ? TipoAjustePrecio.sumarPorcentaje : TipoAjustePrecio.sumarMonto,
            valor: _porcentaje ? (_numero * 100).round() : _numero.round() * centavosPorPeso,
            usuarioId: widget.usuarioId,
          );
        case _Op.pedido:
          await widget.servicio.ajustarStockEnLote(productoIds: ids, tipo: TipoAjusteStock.sumar, valor: _numero.round(), usuarioId: widget.usuarioId, motivo: 'Pedido recibido');
        case _Op.proveedor:
          await widget.servicio.asignarProveedorEnLote(productoIds: ids, proveedorId: _proveedor, usuarioId: widget.usuarioId);
        case _Op.categoria:
          await widget.servicio.asignarCategoriaEnLote(productoIds: ids, categoriaId: _categoria, usuarioId: widget.usuarioId);
      }
      if (!mounted) return;
      navegador.pop(true);
      mostrarAvisoEnNs(overlay, 'Cambios aplicados a ${ids.length} ${ids.length == 1 ? 'producto' : 'productos'}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _aplicando = false;
          _error = mensajeDeError(e);
        });
      }
    }
  }

  static const _nombres = {
    _Op.precios: 'Subir precios',
    _Op.costos: 'Subir costos',
    _Op.pedido: 'Cargar un pedido',
    _Op.proveedor: 'Cambiar proveedor',
    _Op.categoria: 'Cambiar categoría',
  };

  @override
  Widget build(BuildContext context) {
    final n = widget.productos.length;
    if (_revisando) return _revision(context, n);
    final ns = context.ns;
    return HojaNs(
      titulo: '$n ${n == 1 ? 'producto seleccionado' : 'productos seleccionados'}',
      bloques: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué querés hacer con los productos elegidos?', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final o in _Op.values) ChipNs(texto: _nombres[o]!, activo: _op == o, onTap: () => setState(() => _op = o))]),
          ],
        ),
        if (_esMonto) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cómo', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [ChipNs(texto: 'Porcentaje (%)', activo: _porcentaje, onTap: () => setState(() => _porcentaje = true)), ChipNs(texto: 'Monto en pesos', activo: !_porcentaje, onTap: () => setState(() => _porcentaje = false))]),
            ],
          ),
          CampoNs(etiqueta: _porcentaje ? 'Porcentaje a sumar' : 'Monto a sumar', controller: _valor, grande: true, placeholder: '0', teclado: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          const InfoNs('Se aplica al precio de venta de cada producto marcado.'),
          if (_ejemplo != null) InfoNs(_ejemplo!),
        ],
        if (_op == _Op.pedido) CampoNs(etiqueta: 'Unidades a sumar', controller: _valor, grande: true, placeholder: '0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {})),
        if (_op == _Op.proveedor) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [for (final p in widget.proveedores) ChipNs(texto: p.nombre, activo: _proveedor == p.id, onTap: () => setState(() => _proveedor = p.id))]),
          const InfoNs('El proveedor elegido reemplaza el actual en los productos marcados.'),
        ],
        if (_op == _Op.categoria) Wrap(spacing: 8, runSpacing: 8, children: [for (final c in widget.categorias) ChipNs(texto: c.nombre, activo: _categoria == c.id, onTap: () => setState(() => _categoria = c.id))]),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs(
          texto: 'Revisar',
          onTap: () {
            if (!_listo) {
              mostrarAvisoNs(context, 'Escribí un valor mayor a cero');
              return;
            }
            setState(() => _revisando = true);
          },
          alto: 60,
          tamanio: 17,
          fondo: _listo ? ns.prim : ns.s,
          color: _listo ? TokensNs.blanco : ns.mute,
        ),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }

  Widget _revision(BuildContext context, int n) {
    final aviso = _esMonto && _porcentaje && _numero > 50;
    return HojaNs(
      titulo: 'Vas a aplicar esto:',
      bloques: [
        HeroNs(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$n ${n == 1 ? 'producto' : 'productos'}', style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
              const SizedBox(height: 6),
              Text(_resumen, style: tituloNs(30, track: -0.045, altura: 1.1, color: TokensNs.blanco)),
            ],
          ),
        ),
        if (aviso) const InfoNs('Revisá: puede que te haya sobrado un dígito.', tono: TonoNs.warn),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, _aplicando ? 'Aplicando…' : 'Sí, aplicar', _aplicando ? null : _aplicar, habilitado: !_aplicando),
        BotonNs.secundario(context, 'Volver', _aplicando ? null : () => setState(() => _revisando = false)),
      ],
    );
  }
}
