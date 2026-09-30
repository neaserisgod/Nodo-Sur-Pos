// Arma una `LineaVenta` a partir de un resultado de `buscarVenta` (El dueño,
// 2026-09-07: "que la parte de vender use la misma lógica que la app de
// desktop") — mismo mapeo que `lineaDesdeProducto`
// (`data/repositorio_ventas.dart`), pero desde `ProductoCompanion` en vez
// de una fila de drift, porque el celular nunca abre la base. El precio y
// el costo quedan congelados acá (Regla 2, costo-foto): no se vuelven a
// pedir al servidor al calcular ni al cobrar.

import '../domain/venta.dart';
import 'cliente_companion.dart';

/// `linea` es no nulo cuando el producto se pudo agregar tal cual. Si no,
/// `error` trae el mismo mensaje que mostraría
/// `VentaControlador.agregarProducto` para el mismo caso (Regla 7: un
/// pesable sin gramos o sin precio por kilo es un error, no un cero
/// silencioso).
class ResultadoAgregarLinea {
  final LineaVenta? linea;
  final String? error;
  const ResultadoAgregarLinea.ok(LineaVenta this.linea) : error = null;
  const ResultadoAgregarLinea.error(String this.error) : linea = null;
}

ResultadoAgregarLinea lineaDesdeResultadoBusqueda(
  ProductoCompanion producto, {
  int? gramos,
}) {
  final proveedorId = producto.proveedorId?.toString();

  if (producto.esPesable) {
    if (gramos == null || gramos <= 0) {
      return ResultadoAgregarLinea.error(
        'Escribí los gramos antes del nombre, por ejemplo "200 ${producto.nombre}"',
      );
    }
    if (producto.precioPorKiloCentavos == null) {
      return ResultadoAgregarLinea.error(
        '${producto.nombre} no tiene precio por kilo cargado (Regla 7) — cargalo en Productos antes de venderlo.',
      );
    }
    return ResultadoAgregarLinea.ok(
      LineaVentaPesable(
        productoId: '${producto.id}',
        nombreProducto: producto.nombre,
        proveedorId: proveedorId,
        gramos: gramos,
        precioPorKiloCentavos: producto.precioPorKiloCentavos!,
        costoPorKiloCentavos: producto.costoPorKiloCentavos,
      ),
    );
  }

  return ResultadoAgregarLinea.ok(
    LineaVentaPorUnidad(
      productoId: '${producto.id}',
      nombreProducto: producto.nombre,
      proveedorId: proveedorId,
      cantidad: 1,
      tipoCigarrillo: tipoCigarrilloDesde(producto.tipoCigarrillo),
      precioUnitarioCentavos: producto.precioCentavos!,
      costoUnitarioCentavos: producto.costoCentavos,
    ),
  );
}
