// Una línea de carrito con ajuste de cantidad — Bruno, 2026-09-07: "no
// puedo agregar más de 1 unidad a la vez de los productos, misma
// funcionalidad que carrito [ya] dije" (tocar el mismo producto en el
// buscador ya sumaba de a uno, pero eso obliga a buscar de nuevo cada
// vez). Mismos gestos que el carrito de la venta real del escritorio:
// botones "−"/"+" para una línea por unidad (restar en 1 saca la línea
// entera), doble tap sobre la cantidad/gramos para tipear el valor exacto
// de un tirón — sin +/- para un pesable, mismo criterio que el escritorio
// (sumar de a un gramo por toque no tiene sentido práctico). Un solo
// widget para los dos carritos del celular (vender, carga histórica),
// Regla 3.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../ui/tema/tokens.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class FilaLineaCarrito extends StatelessWidget {
  const FilaLineaCarrito({
    super.key,
    required this.linea,
    required this.onCambiar,
    required this.onEliminar,
  });

  final LineaVenta linea;

  /// Se llama con la línea ya modificada (misma identidad de producto,
  /// cantidad o gramos nuevos).
  final ValueChanged<LineaVenta> onCambiar;
  final VoidCallback onEliminar;

  LineaVenta _conValor(int valor) {
    final l = linea;
    if (l is LineaVentaPesable) {
      return LineaVentaPesable(
        productoId: l.productoId,
        nombreProducto: l.nombreProducto,
        proveedorId: l.proveedorId,
        gramos: valor,
        precioPorKiloCentavos: l.precioPorKiloCentavos,
        costoPorKiloCentavos: l.costoPorKiloCentavos,
      );
    }
    final u = l as LineaVentaPorUnidad;
    return LineaVentaPorUnidad(
      productoId: u.productoId,
      nombreProducto: u.nombreProducto,
      proveedorId: u.proveedorId,
      cantidad: valor,
      esVarios: u.esVarios,
      tipoCigarrillo: u.tipoCigarrillo,
      precioUnitarioCentavos: u.precioUnitarioCentavos,
      costoUnitarioCentavos: u.costoUnitarioCentavos,
    );
  }

  void _ajustar(int delta) {
    final u = linea as LineaVentaPorUnidad;
    final nueva = u.cantidad + delta;
    if (nueva <= 0) {
      onEliminar();
      return;
    }
    onCambiar(_conValor(nueva));
  }

  Future<void> _editarExacto(BuildContext context) async {
    final esPesable = linea is LineaVentaPesable;
    final actual = esPesable
        ? (linea as LineaVentaPesable).gramos
        : (linea as LineaVentaPorUnidad).cantidad;
    final controller = TextEditingController(text: '$actual');
    final valor = await mostrarHojaVidrio<int>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(esPesable ? 'Gramos' : 'Cantidad', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Espaciado.lg),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (texto) =>
                Navigator.of(context).pop(int.tryParse(texto)),
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(int.tryParse(controller.text)),
                  child: const Text('Listo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (valor == null) return;
    if (valor <= 0) {
      onEliminar();
      return;
    }
    onCambiar(_conValor(valor));
  }

  @override
  Widget build(BuildContext context) {
    final esPorUnidad = linea is LineaVentaPorUnidad;
    final detalle = switch (linea) {
      LineaVentaPesable l => '${l.gramos} g',
      LineaVentaPorUnidad l => 'x${l.cantidad}',
    };
    // `ListTile` crudo (Bruno, 2026-09-13: "hay algo más sin el
    // lenguaje?") — el carrito es de las pantallas más usadas de la
    // companion, no tenía sentido que se quedara con el look de fábrica.
    return Superficie(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espaciado.lg,
          vertical: Espaciado.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linea.nombreProducto,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  GestureDetector(
                    onDoubleTap: () => _editarExacto(context),
                    child: Text(
                      detalle,
                      style: TextStyle(color: context.colores.textoSecundario),
                    ),
                  ),
                ],
              ),
            ),
            if (esPorUnidad) ...[
              IconButton(
                icon: const Icon(IconosPlazoleta.removeCircleOutline),
                onPressed: () => _ajustar(-1),
              ),
              IconButton(
                icon: const Icon(IconosPlazoleta.addCircleOutline),
                onPressed: () => _ajustar(1),
              ),
            ],
            Text(
              formatearARS(linea.subtotalCentavos),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: Icon(IconosPlazoleta.deleteOutline, color: context.colores.textoSecundario),
              onPressed: onEliminar,
            ),
          ],
        ),
      ),
    );
  }
}
