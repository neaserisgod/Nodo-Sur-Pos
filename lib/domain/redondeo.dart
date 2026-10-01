// Redondeo del total de venta según el medio de pago (Regla 2).
//
// Es plata real (~50 por venta, ~3.000 por día según la estimación del
// negocio): por eso el monto redondeado se expone como valor propio en vez
// de perderse dentro del total, para que en el cierre no se confunda con
// una diferencia de caja.

import 'dinero.dart';
import 'medio_pago.dart';

class ResultadoRedondeo {
  /// Total a cobrar, ya redondeado si correspondía.
  final int totalCentavos;

  /// Cuánto se sumó por redondeo (0 si no correspondía). Siempre >= 0: la
  /// regla es redondear hacia arriba, nunca hacia abajo.
  final int montoRedondeoCentavos;

  const ResultadoRedondeo({
    required this.totalCentavos,
    required this.montoRedondeoCentavos,
  });
}

/// Aplica el redondeo del total según cómo se compone el pago.
///
/// Efectivo y mixto redondean hacia arriba al [pasoCentavos] configurado
/// ("hay efectivo de por medio" en ambos, Regla 2). Virtual puro no
/// redondea: se cobra el importe exacto.
ResultadoRedondeo redondeoDeVenta({
  required int totalCentavos,
  required ComposicionPago composicionPago,
  required int pasoCentavos,
}) {
  // Un paso ≤ 0 (configuración rota) no puede trabar el cobro: se cobra el
  // total exacto, sin redondeo. El valor se rechaza al guardarlo
  // (`configurarPasoRedondeo`); esto es la última defensa.
  if (!composicionPago.incluyeEfectivo || pasoCentavos <= 0) {
    return ResultadoRedondeo(totalCentavos: totalCentavos, montoRedondeoCentavos: 0);
  }
  final redondeado = redondearHaciaArriba(totalCentavos, pasoCentavos);
  return ResultadoRedondeo(
    totalCentavos: redondeado,
    montoRedondeoCentavos: redondeado - totalCentavos,
  );
}
