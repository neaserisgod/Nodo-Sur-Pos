// Reconstruye una `LineaParaReposicion` (lib/domain/reposicion.dart) desde
// una fila cruda de `lineas_de_venta`. Un solo lugar (Regla 3): lo usan
// repositorio_cierre.dart, repositorio_reposicion.dart y
// repositorio_equilibrio.dart, y los tres necesitan exactamente la misma
// conversión precio/costo → subtotal, incluido el caso pesable.

import '../domain/pesables.dart';
import '../domain/reposicion.dart';
import 'database.dart';

/// [venta] (la fila de la venta de esa línea) hace que el precio salga NETO
/// del descuento de la venta, prorrateado por peso de cada línea: sin eso la
/// ganancia, el vendido y el equilibrio contaban a precio de lista una venta
/// que se cobró con descuento (Cliente Frecuente 15%) y sobreestimaban lo que el dueño
/// puede retirar (revisión 2026-09-29). Sin [venta] devuelve el precio de
/// lista — lo que necesita la lata de cigarrillos (Regla 6).
LineaParaReposicion lineaParaReposicionDesde(FilaLineaVenta linea, {FilaVenta? venta}) {
  final precioDeLista = linea.esPesable
      ? subtotalPesable(montoPorKiloCentavos: linea.precioUnitarioCentavos, gramos: linea.gramos!)
      : linea.precioUnitarioCentavos * (linea.cantidad ?? 1);
  final precioLineaCentavos = precioDeLista - _descuentoDeLinea(precioDeLista, venta);

  // Un costo $0 guardado es un costo sin cargar, no mercadería gratis (Regla
  // 4): tomarlo como costo inventaría una ganancia del 100% en Equilibrio,
  // Proveedores y la reposición. Mismo criterio que el backfill de v37.
  // Un servicio sin insumos (un corte) sí cuesta $0 de verdad (Regla 20): no es un costo que falta.
  final guardado = linea.costoUnitarioCentavos;
  final costoUnitario = (guardado == null || (guardado <= 0 && !linea.esServicio)) ? null : guardado;
  final costoLineaCentavos = costoUnitario == null
      ? null
      : linea.esPesable
          ? subtotalPesable(montoPorKiloCentavos: costoUnitario, gramos: linea.gramos!)
          : costoUnitario * (linea.cantidad ?? 1);

  return LineaParaReposicion(
    proveedorId: linea.proveedorIdFoto?.toString(),
    esCigarrillo: linea.tipoCigarrillo != 'ninguno',
    costoLineaCentavos: costoLineaCentavos,
    precioLineaCentavos: precioLineaCentavos,
  );
}

/// Parte del descuento de [venta] que le toca a una línea de [precioLinea]:
/// proporcional a su precio sobre la base en que se calculó el descuento
/// (subtotal + recargo de cigarrillos, ver `calcularTotalVenta`).
int _descuentoDeLinea(int precioLinea, FilaVenta? venta) {
  if (venta == null || venta.descuentoCentavos <= 0) return 0;
  final base = venta.subtotalCentavos + venta.recargoCigarrillosCentavos;
  if (base <= 0) return 0;
  return (precioLinea * venta.descuentoCentavos + base ~/ 2) ~/ base;
}
