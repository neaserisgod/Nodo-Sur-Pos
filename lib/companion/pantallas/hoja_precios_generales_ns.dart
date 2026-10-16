// Precios de todo el catálogo desde el celular (El dueño, 2026-10-16, `domain/precios_generales.dart`), en markup sobre el
// costo: subir todo X % (al precio se le suma el X % del costo), igualar el markup de todos a X %, y deshacer la última suba.
// Cigarrillos y fiambres nunca se tocan. Antes de aplicar se dice a cuántos productos les cambia el precio.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart' show redondearHaciaArriba;
import '../../domain/edicion_masiva_precios.dart';
import '../../domain/precios_generales.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

/// [categorias]: nombre de cada categoría por id (para reconocer los fiambres).
ProductoParaPrecios paraPreciosNs(ProductoCompanion p, Map<int, String> categorias) => productoParaPrecios(
      precioCentavos: p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos,
      costoCentavos: p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos,
      tipoCigarrillo: p.tipoCigarrillo,
      esPesable: p.esPesable,
      nombreCategoria: categorias[p.categoriaId],
    );

/// "38 %" o "37,5 %".
String textoPorcentajeNs(int bp) {
  final entero = bp ~/ 100, resto = (bp.abs() % 100);
  if (resto == 0) return '$entero %';
  final dec = resto % 10 == 0 ? '${resto ~/ 10}' : resto.toString().padLeft(2, '0');
  return '$entero,$dec %';
}

/// "12,5" → 1250. Null si no es un porcentaje.
int? leerPorcentajeBp(String texto) {
  final t = texto.trim().replaceAll('%', '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
  return (double.parse(t) * 100).round();
}

/// Abre la hoja. Devuelve true si se cambió algún precio.
Future<bool> mostrarHojaPreciosGenerales(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
  required List<ProductoCompanion> productos,
  required Map<int, String> categorias,
}) async =>
    await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaPreciosGenerales(servicio: servicio, usuarioId: usuarioId, productos: productos, categorias: categorias),
    ) ??
    false;

class _HojaPreciosGenerales extends StatefulWidget {
  const _HojaPreciosGenerales({required this.servicio, required this.usuarioId, required this.productos, required this.categorias});
  final ServicioCompanion servicio;
  final int usuarioId;
  final List<ProductoCompanion> productos;
  final Map<int, String> categorias;

  @override
  State<_HojaPreciosGenerales> createState() => _HojaPreciosGeneralesState();
}

class _HojaPreciosGeneralesState extends State<_HojaPreciosGenerales> {
  final _valor = TextEditingController();
  int _modo = 0; // 0 = subir todo, 1 = igualar el markup, 2 = deshacer la última suba
  int _redondeo = 3; // índice de [_pasos]: $100 por defecto, como el precio por porcentaje del proveedor (Regla 14)
  static const _pasos = [100, 1000, 5000, 10000];

  int get _pasoCentavos => _pasos[_redondeo];

  /// "Subir todo" con 0 % solo redondea (El dueño, 2026-10-16: "me dejó todos los precios con números sin redondear").
  bool _sirve(int? bp) => bp != null && (bp > 0 || (_modo == 0 && bp == 0 && _pasoCentavos > 100));
  bool _aplicando = false;
  String? _error;
  ({int productos, DateTime? cuando})? _deshacer;

  @override
  void initState() {
    super.initState();
    _contarDeshacer();
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  Future<void> _contarDeshacer() async {
    try {
      final r = await widget.servicio.deshacerUltimaSuba(usuarioId: widget.usuarioId, soloContar: true);
      if (mounted) setState(() => _deshacer = r);
    } catch (_) {
      if (mounted) setState(() => _deshacer = (productos: 0, cuando: null));
    }
  }

  ProductoParaPrecios _pp(ProductoCompanion p) => paraPreciosNs(p, widget.categorias);

  /// A cuántos les cambia el precio con lo escrito. Null si lo escrito no sirve.
  int? _cuantosCambian(int? bp) {
    if (_modo == 2) return _deshacer?.productos;
    if (!_sirve(bp)) return null;
    return widget.productos.where((p) {
      final nuevo = _nuevo(p, bp!);
      return nuevo != null && nuevo != _pp(p).precioCentavos;
    }).length;
  }

  Future<void> _aplicar(int bp) async {
    final navegador = Navigator.of(context);
    setState(() {
      _aplicando = true;
      _error = null;
    });
    try {
      final cambiados = switch (_modo) {
        0 => await _subirTodo(bp),
        1 => await widget.servicio.igualarMarkupGeneral(markupBp: bp, usuarioId: widget.usuarioId),
        _ => (await widget.servicio.deshacerUltimaSuba(usuarioId: widget.usuarioId)).productos,
      };
      if (!mounted) return;
      mostrarAvisoNs(context, cambiados == 1 ? 'Cambió 1 precio' : 'Cambiaron $cambiados precios');
      navegador.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _aplicando = false);
    }
  }

  /// El precio que le queda a [p] con lo elegido. Null si no se toca.
  int? _nuevo(ProductoCompanion p, int bp) {
    final pp = _pp(p);
    if (_modo == 1) return precioAlIgualarMarkup(pp, bp);
    // Solo redondear (0 %): también los que no tienen costo.
    if (bp == 0) return entraEnRedondeo(pp) ? redondearHaciaArriba(pp.precioCentavos!, _pasoCentavos) : null;
    return precioAlSubirSobreCosto(pp, bp, redondeoCentavos: _pasoCentavos);
  }

  /// "Subir todo" es la edición en lote con todos los productos que entran (Regla 3: la misma fórmula y el mismo camino).
  Future<int> _subirTodo(int bp) async {
    final ids = [
      for (final p in widget.productos)
        if (_nuevo(p, bp) case final nuevo? when nuevo != _pp(p).precioCentavos) p.id,
    ];
    if (ids.isEmpty) return 0;
    await widget.servicio.ajustarMontoEnLote(
      productoIds: ids,
      campo: CampoMonto.precio,
      // Con 0 % es "sumar $0" redondeado: la misma edición en lote, solo redondea.
      tipo: bp == 0 ? TipoAjustePrecio.sumarMonto : TipoAjustePrecio.sumarPorcentajeDelCosto,
      valor: bp,
      usuarioId: widget.usuarioId,
      redondeoCentavos: _pasoCentavos,
    );
    return ids.length;
  }

  String _ejemplo(int? bp) {
    // Con un producto real si hay: así se ve la cuenta antes de aplicarla.
    for (final p in widget.productos) {
      final pp = _pp(p);
      final nuevo = _sirve(bp) ? _nuevo(p, bp!) : null;
      if (nuevo != null && nuevo != pp.precioCentavos) {
        final costo = pp.costoCentavos == null ? '' : ', costo ${plataNs(pp.costoCentavos!)}';
        return 'Ej.: ${p.nombre}$costo: de ${plataNs(pp.precioCentavos ?? 0)} a ${plataNs(nuevo)}.';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final promedio = promedioDePrecios(widget.productos.map(_pp));
    final bp = leerPorcentajeBp(_valor.text);
    final cuantos = _cuantosCambian(bp);
    final listo = cuantos != null && cuantos > 0 && !_aplicando;
    final d = _deshacer;
    return HojaNs(
      titulo: 'Precios de todo',
      texto: promedio == null
          ? 'Todavía no hay productos con costo para calcular el markup promedio.'
          : 'Markup promedio: ${textoPorcentajeNs(promedio.markupBp)} sobre el costo (ganancia de ${textoPorcentajeNs(promedio.gananciaBp)} '
              'sobre el precio), de ${promedio.productos} productos. Cigarrillos y fiambres no cuentan ni se tocan.',
      bloques: [
        SegmentoNs(opciones: const ['Subir todo', 'Igualar', 'Deshacer'], indice: _modo, onCambio: (i) => setState(() => _modo = i)),
        const SizedBox(height: 12),
        Text(
          switch (_modo) {
            0 => 'El markup de cada producto sube ese porcentaje: al precio se le suma ese % del costo, redondeado para arriba. Quedan '
                'como precio fijo. Los que no tienen costo no se tocan. Con 0 % solo se redondean los precios.',
            1 => 'Todos los productos con costo quedan con ese markup (redondeado a la centena) y todos los proveedores pasan a ese %. '
                'Los de precio fijo también.',
            _ => 'Cada producto de la última suba de todo vuelve al precio que tenía antes. Los que tocaste a mano después no cambian.',
          },
          style: estiloNs(14, altura: 1.4, color: ns.mute),
        ),
        const SizedBox(height: 12),
        if (_modo < 2) ...[
          CampoNs(
            key: const Key('precios_generales_valor'),
            etiqueta: _modo == 0 ? 'Cuánto sube el markup (%)' : 'Markup para todos (%)',
            controller: _valor,
            placeholder: _modo == 0 ? 'Ej: 15' : 'Ej: ${promedio == null ? 70 : (promedio.markupBp / 100).round()}',
            teclado: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (_modo == 0) ...[
            const SizedBox(height: 12),
            Text('Redondear para arriba a', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
            const SizedBox(height: 8),
            SegmentoNs(opciones: const ['\$1', '\$10', '\$50', '\$100'], indice: _redondeo, onCambio: (i) => setState(() => _redondeo = i)),
          ],
          const SizedBox(height: 10),
          if (_valor.text.trim().isNotEmpty)
            InfoNs(
              cuantos == null
                  ? (_modo == 0 ? 'Escribí un porcentaje, por ejemplo 15 (o 0 para solo redondear a más de \$1).' : 'Escribí un porcentaje, por ejemplo 70.')
                  : cuantos == 0
                      ? 'Con ese porcentaje no cambia ningún precio.'
                      : 'Cambia el precio de $cuantos ${cuantos == 1 ? 'producto' : 'productos'}. ${_ejemplo(bp)}',
              tono: cuantos == null ? TonoNs.warn : TonoNs.info,
            ),
        ] else
          InfoNs(
            d == null
                ? 'Buscando la última suba…'
                : d.productos == 0
                    ? 'No hay una suba de todo para deshacer en los últimos 30 días.'
                    : 'Vuelven ${d.productos} ${d.productos == 1 ? 'producto' : 'productos'} al precio de antes de la suba del '
                        '${d.cuando!.day}/${d.cuando!.month} a las ${d.cuando!.hour}:${d.cuando!.minute.toString().padLeft(2, '0')}.',
            tono: TonoNs.info,
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        ],
      ],
      botones: [
        BotonNs.primario(context, _aplicando ? 'Aplicando…' : (_modo == 2 ? 'Deshacer' : 'Aplicar'), listo ? () => _aplicar(bp ?? 0) : null, habilitado: listo),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
