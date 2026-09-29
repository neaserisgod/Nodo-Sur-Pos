// Stock derivado del log de movimientos (fase 1 del rediseño de la companion
// Android para operar sin depender del escritorio, 2026-09-15) — no una
// fórmula de venta nueva, es cómo dos bases SQLite independientes (escritorio
// y celular) pueden mergear ventas hechas offline en paralelo sin que una le
// pise el conteo a la otra.
//
// Hoy `productos.stock` es un contador absoluto que cada venta mutila
// in-place (`registrarLineaDeVenta`, `repositorio_ventas.dart`). Si dos
// dispositivos venden el mismo producto sin verse y después se sincroniza esa
// columna directamente, gana el que sincronizó último y la otra venta
// desaparece del conteo (aunque la venta en sí quede bien grabada). La
// solución no es elegir un ganador: es dejar de sincronizar el contador y
// sincronizar en cambio el LOG de movimientos (append-only, dos movimientos
// con id propio nunca se pisan) y derivar el número acá.

/// Cuánto cambió un movimiento de stock ya persistido. [anterior]/[posterior]
/// son los mismos valores que `movimientos_de_stock` ya fotografía al grabar
/// cada fila (Regla 6 de negocio: todo movimiento deja rastro) — esta clase
/// no reinterpreta `tipo`/`cantidad`/`gramos` para inferir el delta de nuevo,
/// eso ya se decidió una sola vez en el momento de grabar el movimiento
/// (Regla 3 de convenciones: una sola fórmula, no dos).
class DeltaStock {
  final int anterior;
  final int posterior;

  const DeltaStock({required this.anterior, required this.posterior});

  int get delta => posterior - anterior;
}

/// Stock final = una base ya conocida y confiable, más la suma de lo que
/// cambió cada movimiento nuevo que se sincronizó después de esa base.
///
/// El orden de [movimientos] no importa: sumar deltas es conmutativo, así
/// que el resultado es el mismo sin importar en qué orden cada dispositivo
/// vio los movimientos del otro — no hace falta un reloj compartido y
/// confiable entre dos dispositivos para que esto dé bien.
///
/// Puede devolver un número negativo — Regla 8 de negocio: el stock informa,
/// nunca bloquea una venta. Esta función no le agrega ni le saca validez a
/// esa regla, solo cambia cómo se sincroniza el número entre dos bases.
int stockRecalculado({
  required int stockBase,
  required List<DeltaStock> movimientos,
}) {
  return movimientos.fold(stockBase, (acumulado, m) => acumulado + m.delta);
}
