// Precios de todo el catálogo desde el celular (El dueño, 2026-10-16, `domain/precios_generales.dart`): subir todos los
// precios X % o igualar la ganancia de todos a X %. Los cigarrillos nunca se tocan. Antes de aplicar se dice a cuántos
// productos les cambia el precio.

import 'package:flutter/material.dart';

import '../../domain/edicion_masiva_precios.dart';
import '../../domain/precios_generales.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

ProductoParaPrecios paraPreciosNs(ProductoCompanion p) => (
      precioCentavos: p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos,
      costoCentavos: p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos,
      esCigarrillo: p.tipoCigarrillo != 'ninguno',
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
}) async =>
    await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaPreciosGenerales(servicio: servicio, usuarioId: usuarioId, productos: productos),
    ) ??
    false;

class _HojaPreciosGenerales extends StatefulWidget {
  const _HojaPreciosGenerales({required this.servicio, required this.usuarioId, required this.productos});
  final ServicioCompanion servicio;
  final int usuarioId;
  final List<ProductoCompanion> productos;

  @override
  State<_HojaPreciosGenerales> createState() => _HojaPreciosGeneralesState();
}

class _HojaPreciosGeneralesState extends State<_HojaPreciosGenerales> {
  final _valor = TextEditingController();
  int _modo = 0; // 0 = subir todo, 1 = igualar la ganancia
  bool _aplicando = false;
  String? _error;

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  List<ProductoCompanion> get _subibles => [for (final p in widget.productos) if (entraEnSubaGeneral(paraPreciosNs(p))) p];

  /// A cuántos les cambia el precio con lo escrito. Null si lo escrito no sirve.
  int? _cuantosCambian(int? bp) {
    if (bp == null || bp <= 0) return null;
    if (_modo == 0) return _subibles.length;
    if (bp >= 10000) return null;
    return widget.productos.where((p) {
      final nuevo = precioAlIgualarGanancia(paraPreciosNs(p), bp);
      return nuevo != null && nuevo != paraPreciosNs(p).precioCentavos;
    }).length;
  }

  Future<void> _aplicar(int bp) async {
    final navegador = Navigator.of(context);
    setState(() {
      _aplicando = true;
      _error = null;
    });
    try {
      final int cambiados;
      if (_modo == 0) {
        final ids = [for (final p in _subibles) p.id];
        await widget.servicio.ajustarMontoEnLote(
          productoIds: ids,
          campo: CampoMonto.precio,
          tipo: TipoAjustePrecio.sumarPorcentaje,
          valor: bp,
          usuarioId: widget.usuarioId,
        );
        cambiados = ids.length;
      } else {
        cambiados = await widget.servicio.igualarGananciaGeneral(gananciaBp: bp, usuarioId: widget.usuarioId);
      }
      if (!mounted) return;
      mostrarAvisoNs(context, cambiados == 1 ? 'Cambió 1 precio' : 'Cambiaron $cambiados precios');
      navegador.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _aplicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final promedio = gananciaPromedio(widget.productos.map(paraPreciosNs));
    final bp = leerPorcentajeBp(_valor.text);
    final cuantos = _cuantosCambian(bp);
    final listo = cuantos != null && cuantos > 0 && !_aplicando;
    return HojaNs(
      titulo: 'Precios de todo',
      texto: promedio == null
          ? 'Todavía no hay productos con costo para calcular la ganancia promedio.'
          : 'Ganancia promedio: ${textoPorcentajeNs(promedio.gananciaBp)} sobre el precio, de ${promedio.productos} productos con costo. '
              'Los cigarrillos no cuentan ni se tocan.',
      bloques: [
        SegmentoNs(opciones: const ['Subir todo', 'Igualar ganancia'], indice: _modo, onCambio: (i) => setState(() => _modo = i)),
        const SizedBox(height: 12),
        Text(
          _modo == 0
              ? 'Todos los precios suben ese porcentaje (redondeado al peso) y quedan como precio fijo: el % del proveedor ya no los cambia.'
              : 'Todos los productos con costo quedan con esa ganancia sobre el precio (redondeado a la centena), y todos los proveedores pasan a ese %. Los de precio fijo también.',
          style: estiloNs(14, altura: 1.4, color: ns.mute),
        ),
        const SizedBox(height: 12),
        CampoNs(
          key: const Key('precios_generales_valor'),
          etiqueta: _modo == 0 ? 'Cuánto suben (%)' : 'Ganancia para todos (%)',
          controller: _valor,
          placeholder: _modo == 0 ? 'Ej: 10' : 'Ej: ${promedio == null ? 35 : (promedio.gananciaBp / 100).round()}',
          teclado: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (_valor.text.trim().isNotEmpty)
          InfoNs(
            cuantos == null
                ? (_modo == 1 && (bp ?? 0) >= 10000 ? 'La ganancia tiene que ser menor a 100 %.' : 'Escribí un porcentaje, por ejemplo 12,5.')
                : cuantos == 0
                    ? 'Con ese porcentaje no cambia ningún precio.'
                    : 'Cambia el precio de $cuantos ${cuantos == 1 ? 'producto' : 'productos'}.',
            tono: cuantos == null ? TonoNs.warn : TonoNs.info,
          ),
        if (_modo == 0 && (bp ?? 0) >= 10000) ...[
          const SizedBox(height: 8),
          const InfoNs('Es más del doble del precio actual: revisá que no te haya sobrado un dígito.', tono: TonoNs.warn),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        ],
      ],
      botones: [
        BotonNs.primario(context, _aplicando ? 'Aplicando…' : 'Aplicar', listo ? () => _aplicar(bp!) : null, habilitado: listo),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
