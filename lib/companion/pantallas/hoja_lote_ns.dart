// Hoja de edición en lote (mock, lote 3): según desde dónde se eligieron los productos cambia lo que se puede hacer.
//   · Productos de un proveedor / selección general → "Recibí un pedido", "Subió el precio", "Subió el costo", con
//     sumar / restar (% o monto) o valor nuevo.
//   · Filtro "Sin proveedor" → asignar proveedor.   · Filtro "Sin categoría" → asignar categoría.
// Siempre pasa por "Confirmar cambio a N productos" antes de aplicar, y avisa si el aumento es de 100 % o más.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../domain/edicion_masiva_precios.dart';
import '../../domain/edicion_masiva_stock.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

enum ContextoLote { proveedor, asignarProveedor, asignarCategoria, general }

/// `true` si se aplicó el cambio.
Future<bool> mostrarHojaLote(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
  required List<ProductoCompanion> productos,
  required List<ProveedorCompanion> proveedores,
  required List<CategoriaCompanion> categorias,
  ContextoLote contexto = ContextoLote.general,
  String? nombreProveedor,
}) async {
  final r = await mostrarHojaNs<bool>(
    context,
    builder: (_) => _HojaLote(servicio: servicio, usuarioId: usuarioId, productos: productos, proveedores: proveedores, categorias: categorias, contexto: contexto, nombreProveedor: nombreProveedor),
  );
  return r ?? false;
}

enum _Que { stock, precio, costo }

class _HojaLote extends StatefulWidget {
  const _HojaLote({required this.servicio, required this.usuarioId, required this.productos, required this.proveedores, required this.categorias, required this.contexto, this.nombreProveedor});
  final ServicioCompanion servicio;
  final int usuarioId;
  final List<ProductoCompanion> productos;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;
  final ContextoLote contexto;
  final String? nombreProveedor;

  @override
  State<_HojaLote> createState() => _HojaLoteState();
}

class _HojaLoteState extends State<_HojaLote> {
  _Que _que = _Que.precio;
  String _tipo = 'Sumar %';
  int? _proveedor; // null = "Sin proveedor"
  int? _categoria; // null = "Sin categoría"
  final _valor = TextEditingController();
  bool _revisando = false;
  bool _aplicando = false;
  String? _error;

  static const _tiposDinero = ['Sumar %', 'Restar %', 'Sumar monto', 'Restar monto', 'Valor nuevo'];
  static const _tiposStock = ['Sumar', 'Restar', 'Valor nuevo'];

  bool get _esAsignar => widget.contexto == ContextoLote.asignarProveedor || widget.contexto == ContextoLote.asignarCategoria;
  bool get _esStock => !_esAsignar && _que == _Que.stock;
  bool get _esDinero => !_esAsignar && _que != _Que.stock;
  bool get _esPct => _tipo.endsWith('%');

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  double get _pct => double.tryParse(_valor.text.trim().replaceAll('%', '').replaceAll(',', '.')) ?? 0;
  int get _numero => int.tryParse(_valor.text.trim().replaceAll('.', '')) ?? 0;

  String _nTxt(double n) => n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2).replaceAll('.', ',');

  String get _campo => _que == _Que.costo ? 'costo' : 'precio de venta';

  /// "Sumar 10% al precio de venta", "Poner el stock en 24"… (la frase de la confirmación).
  String get _frase {
    switch (widget.contexto) {
      case ContextoLote.asignarProveedor:
        final p = widget.proveedores.where((x) => x.id == _proveedor).firstOrNull;
        return 'Poner el proveedor en ${p == null ? '"sin proveedor"' : '"${p.nombre}"'}';
      case ContextoLote.asignarCategoria:
        final c = widget.categorias.where((x) => x.id == _categoria).firstOrNull;
        return 'Poner la categoría en ${c == null ? '"sin categoría"' : '"${c.nombre}"'}';
      default:
    }
    if (_esStock) {
      return switch (_tipo) {
        'Valor nuevo' => 'Poner el stock en $_numero',
        'Sumar' => 'Sumar $_numero al stock',
        _ => 'Restar $_numero al stock',
      };
    }
    final m = plataNs(_numero * centavosPorPeso);
    return switch (_tipo) {
      'Valor nuevo' => 'Poner el $_campo en $m fijo',
      'Sumar monto' => 'Sumar $m al $_campo',
      'Restar monto' => 'Restar $m al $_campo',
      'Sumar %' => 'Sumar ${_nTxt(_pct)}% al $_campo',
      _ => 'Restar ${_nTxt(_pct)}% al $_campo',
    };
  }

  String get _advertencia {
    if (!(_esDinero && _esPct && _pct >= 100)) return '';
    if (_tipo == 'Restar %') return 'Restar ${_nTxt(_pct)}% deja el precio en \$0 en todos los productos marcados.';
    return 'Es un aumento de ${_nTxt(_pct)}% — más del doble del valor actual. Revisá que no te haya sobrado un dígito o faltado el punto decimal (ej. "500" en vez de "50").';
  }

  /// Valida lo escrito antes de pasar a la confirmación; devuelve el error o null.
  String? _validar() {
    if (_esAsignar) return null;
    final raw = _valor.text.trim();
    if (_esStock) return RegExp(r'^\d+$').hasMatch(raw) ? null : 'Valor inválido';
    if (_esPct) return RegExp(r'^\d+([.,]\d+)?%?$').hasMatch(raw) ? null : 'Porcentaje inválido';
    if (raw.startsWith('-')) return 'El monto no puede ser negativo';
    return RegExp(r'^\d+$').hasMatch(raw.replaceAll('.', '')) ? null : 'Monto inválido';
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
      switch (widget.contexto) {
        case ContextoLote.asignarProveedor:
          await widget.servicio.asignarProveedorEnLote(productoIds: ids, proveedorId: _proveedor, usuarioId: widget.usuarioId);
        case ContextoLote.asignarCategoria:
          await widget.servicio.asignarCategoriaEnLote(productoIds: ids, categoriaId: _categoria, usuarioId: widget.usuarioId);
        default:
          if (_esStock) {
            await widget.servicio.ajustarStockEnLote(
              productoIds: ids,
              tipo: switch (_tipo) {
                'Sumar' => TipoAjusteStock.sumar,
                'Restar' => TipoAjusteStock.restar,
                _ => TipoAjusteStock.nuevoFijo,
              },
              valor: _numero,
              usuarioId: widget.usuarioId,
              motivo: _tipo == 'Sumar' ? 'Pedido recibido' : 'Ajuste en lote',
            );
          } else {
            await widget.servicio.ajustarMontoEnLote(
              productoIds: ids,
              campo: _que == _Que.costo ? CampoMonto.costo : CampoMonto.precio,
              tipo: switch (_tipo) {
                'Sumar %' => TipoAjustePrecio.sumarPorcentaje,
                'Restar %' => TipoAjustePrecio.restarPorcentaje,
                'Sumar monto' => TipoAjustePrecio.sumarMonto,
                'Restar monto' => TipoAjustePrecio.restarMonto,
                _ => TipoAjustePrecio.nuevoFijo,
              },
              valor: _esPct ? (_pct * 100).round() : _numero * centavosPorPeso,
              usuarioId: widget.usuarioId,
            );
          }
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

  Widget _grupo(String etiqueta, List<Widget> chips) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(etiqueta, style: estiloNs(14, peso: FontWeight.w600, color: context.ns.mute)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: chips),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final n = widget.productos.length;
    if (_revisando) return _confirmacion(context, n);
    final cuenta = '$n ${n == 1 ? 'producto seleccionado' : 'productos seleccionados'}';
    final titulo = switch (widget.contexto) {
      ContextoLote.proveedor => 'Productos de ${widget.nombreProveedor ?? ''}',
      ContextoLote.general => 'Editar en lote',
      ContextoLote.asignarProveedor => 'Asignar proveedor',
      ContextoLote.asignarCategoria => 'Asignar categoría',
    };
    final tipos = _esStock ? _tiposStock : _tiposDinero;
    final etiquetaCampo = _esStock
        ? {'Sumar': 'Unidades a sumar', 'Restar': 'Unidades a restar', 'Valor nuevo': 'Stock nuevo'}[_tipo]!
        : {'Sumar %': 'Porcentaje a sumar (%)', 'Restar %': 'Porcentaje a restar (%)', 'Sumar monto': 'Monto a sumar', 'Restar monto': 'Monto a restar', 'Valor nuevo': 'Valor nuevo'}[_tipo]!;
    final cuerpo = <Widget>[
      if (widget.contexto == ContextoLote.asignarProveedor) ...[
        const InfoNs('El proveedor elegido reemplaza el actual en los productos marcados.'),
        _grupo('Proveedor', [
          ChipNs(texto: 'Sin proveedor', activo: _proveedor == null, onTap: () => setState(() => _proveedor = null)),
          for (final p in widget.proveedores) ChipNs(texto: '${p.codigo} — ${p.nombre}', activo: _proveedor == p.id, onTap: () => setState(() => _proveedor = p.id)),
        ]),
      ] else if (widget.contexto == ContextoLote.asignarCategoria) ...[
        const InfoNs('La categoría elegida reemplaza la actual en los productos marcados.'),
        _grupo('Categoría', [
          ChipNs(texto: 'Sin categoría', activo: _categoria == null, onTap: () => setState(() => _categoria = null)),
          for (final c in widget.categorias) ChipNs(texto: c.nombre, activo: _categoria == c.id, onTap: () => setState(() => _categoria = c.id)),
        ]),
      ] else ...[
        _grupo('¿Qué querés hacer?', [
          for (final (q, l) in [(_Que.stock, 'Recibí un pedido'), (_Que.precio, 'Subió el precio'), (_Que.costo, 'Subió el costo')])
            ChipNs(
              texto: l,
              activo: _que == q,
              onTap: () => setState(() {
                _que = q;
                _tipo = q == _Que.stock ? 'Sumar' : 'Sumar %';
                _valor.clear();
                _error = null;
              }),
            ),
        ]),
        InfoNs(
          _esStock
              ? 'Ajusta el stock de cada producto marcado — unidades, o gramos si es pesable. Deja rastro en movimientos de stock, igual que un ajuste uno por uno.'
              : _que == _Que.costo
              ? 'Se aplica al costo de cada producto marcado — el precio de venta no se toca.'
              : 'Se aplica al precio de venta de cada producto marcado.',
        ),
        _grupo('Cómo', [
          for (final t in tipos)
            ChipNs(
              texto: t,
              activo: _tipo == t,
              onTap: () => setState(() {
                _tipo = t;
                _valor.clear();
                _error = null;
              }),
            ),
        ]),
        CampoNs(
          key: ValueKey('lote:$_que:$_tipo'),
          etiqueta: etiquetaCampo,
          controller: _valor,
          grande: true,
          placeholder: '0',
          teclado: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() => _error = null),
        ),
      ],
      if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
    ];
    return HojaNs(
      titulo: titulo,
      texto: cuenta,
      bloques: cuerpo,
      botones: [
        BotonNs.primario(context, 'Revisar', () {
          final e = _validar();
          if (e != null) {
            setState(() => _error = e);
            return;
          }
          setState(() {
            _revisando = true;
            _error = null;
          });
        }),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }

  Widget _confirmacion(BuildContext context, int n) {
    final cuenta = '$n ${n == 1 ? 'producto' : 'productos'}';
    final aviso = _advertencia;
    return HojaNs(
      titulo: 'Confirmar cambio a $cuenta',
      texto: 'Vas a aplicar esto:',
      bloques: [
        SizedBox(
          width: double.infinity,
          child: HeroNs(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cuenta, style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
                const SizedBox(height: 6),
                Text(_frase, style: tituloNs(34, track: -0.05, altura: 1.05, color: TokensNs.blanco)),
                if (aviso.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(aviso, style: estiloNs(14, altura: 1.4, color: const Color(0xCCFFFFFF))),
                ],
              ],
            ),
          ),
        ),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, _aplicando ? 'Aplicando…' : 'Sí, aplicar', _aplicando ? null : _aplicar, habilitado: !_aplicando),
        BotonNs.secundario(context, 'Volver', _aplicando ? null : () => setState(() => _revisando = false)),
      ],
    );
  }
}
