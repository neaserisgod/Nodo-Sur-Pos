// Recargo por pago virtual en ventas con cigarrillos (Regla 6).
//
// Es un sistema paralelo dentro de la misma caja física: Serra Cigarros
// cobra solo en efectivo, así que cuando el cliente paga con QR/Point la
// diferencia de conseguir ese efectivo se cubre con este recargo. Se queda
// en la caja normal — nunca pasa a la lata de cigarrillos (eso lo garantiza
// el módulo `caja`, no este).

import 'medio_pago.dart';

/// Los montos del recargo son configurables (fase 8), no fijos en el
/// código: solo la REGLA de cuándo y cómo se aplican es fija.
///
/// [cigarroSueltoCentavos]: $50 por cigarro suelto (Regla 6) — Bruno,
/// 2026-09-10: "los puchos sueltos también deben tener recargo por MP, sin
/// eso los cálculos dan mal". Antes de esa fecha los sueltos no llevaban
/// recargo; el default 0 de acá abajo es solo el valor de arranque de la
/// clase (nadie lo usa sin pasar el de verdad — los cuatro lugares que
/// arman este objeto en la app real siempre leen `recargoSueltoCentavos`
/// de la configuración guardada).
class ConfigRecargoCigarrillos {
  final int primerAtadoCentavos;
  final int atadoAdicionalCentavos;
  final int cigarroSueltoCentavos;

  const ConfigRecargoCigarrillos({
    required this.primerAtadoCentavos,
    required this.atadoAdicionalCentavos,
    this.cigarroSueltoCentavos = 0,
  });
}

/// Recargo total de la venta por pago virtual, escalonado por cantidad de
/// atados (no porcentual, no fijo por medio de pago — Regla 6 y lección
/// anexa 5 del sistema anterior).
///
/// Se aplica completo si el pago incluye cualquier parte virtual, mixto
/// incluido: "el costo de conseguir el efectivo se paga igual" aunque solo
/// una parte de la venta vaya por QR — no se prorratea.
int recargoCigarrillos({
  required int cantidadAtados,
  required int cantidadSueltos,
  required ComposicionPago composicionPago,
  required ConfigRecargoCigarrillos config,
}) {
  if (!composicionPago.incluyeVirtual) return 0;

  var recargo = 0;
  if (cantidadAtados > 0) {
    recargo += config.primerAtadoCentavos +
        (cantidadAtados - 1) * config.atadoAdicionalCentavos;
  }
  recargo += cantidadSueltos * config.cigarroSueltoCentavos;
  return recargo;
}
