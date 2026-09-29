// Cómo se compone el pago de una venta, a los efectos de dos reglas que
// clasifican por lo mismo: el redondeo del total (Regla 2) y el recargo de
// cigarrillos por pago virtual (Regla 6). No es la lista de medios de pago
// configurables del negocio (efectivo, Mercado Pago, Point...) — eso vive en
// datos, fase 2 — es solo esta clasificación de tres formas que ambas reglas
// necesitan, para no definirla dos veces y que se desalineen.
enum ComposicionPago {
  /// Pago enteramente en efectivo.
  efectivo,

  /// Pago enteramente virtual (QR, Point, etc.), sin ninguna parte en efectivo.
  virtual,

  /// Parte en efectivo, parte virtual.
  mixto,
}

extension ComposicionPagoReglas on ComposicionPago {
  /// true si alguna parte del pago es en efectivo (Regla 2: redondea).
  bool get incluyeEfectivo =>
      this == ComposicionPago.efectivo || this == ComposicionPago.mixto;

  /// true si alguna parte del pago es virtual (Regla 6: dispara el recargo).
  bool get incluyeVirtual =>
      this == ComposicionPago.virtual || this == ComposicionPago.mixto;
}

/// La composición real de un pago se deriva de los montos, no de qué botón
/// se apretó: un "mixto" con una punta en $0 no es un mixto, es efectivo o
/// virtual puro, y tratarlo como mixto igual aplica redondeo a una venta
/// 100% virtual (Regla 2) o el recargo de cigarrillos a una 100% efectivo
/// (Regla 6) — las dos, mal. [totalCentavos] es el total ya calculado como
/// si fuera mixto (recargo + redondeo incluidos, el "peor caso" de las
/// tres composiciones), que es lo que el diálogo de mixto ya usa como techo
/// del monto en efectivo que se puede cargar.
ComposicionPago clasificarComposicion({
  required int montoEfectivoCentavos,
  required int totalCentavos,
}) {
  if (montoEfectivoCentavos <= 0) return ComposicionPago.virtual;
  if (montoEfectivoCentavos >= totalCentavos) return ComposicionPago.efectivo;
  return ComposicionPago.mixto;
}

/// `'efectivo'` | `'virtual'` | `'mixto'` desde texto — el vocabulario que
/// manda el celular (companion Android, HTTP o local) para elegir el medio
/// al calcular o cobrar una venta. Un solo lugar (Regla 3 de convenciones):
/// antes vivía duplicado como `_medioDesdeTexto` en
/// `lib/servidor/servidor_companion.dart`, con el mismo texto exacto — ahora
/// ese archivo y `lib/companion/puerto_local.dart` (vender sin conexión a la
/// PC) llaman a esta única función.
ComposicionPago composicionPagoDesdeTexto(String texto) => switch (texto) {
  'efectivo' => ComposicionPago.efectivo,
  'virtual' => ComposicionPago.virtual,
  'mixto' => ComposicionPago.mixto,
  _ => throw FormatException(
    '"medio" tiene que ser "efectivo", "virtual" o "mixto"',
  ),
};
