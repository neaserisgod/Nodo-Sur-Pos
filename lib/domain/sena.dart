// Seña de encargues (rediseño v4, etapa 8.4; decisiones del dueño del 2026-10-06). Función pura: sin base ni pantalla.
//
// Reglas:
//  - La seña entra en la caja con la que se pagó (cajón si fue efectivo, Mercado Pago si no) como INGRESO de caja, no como venta.
//  - Al entregar y cobrar el encargue se registra UNA venta del día en que se completó, por el total a precios de ese día
//    (Regla 4). Lo ya cobrado de seña es un pago de esa venta que NO vuelve a mover la caja (ya entró cuando se señó).
//  - Si el encargue se cancela, la seña se devuelve por la misma caja con la que entró.
//
// Por qué la seña no es una venta cuando entra: si lo fuera, el día de la seña mostraría una venta sin entrega (y su ganancia,
// su costo y el stock no coinciden con nada), y el día de la entrega la venta vendría "sin plata". Como ingreso, el cajón y
// Mercado Pago cuadran todos los días y la venta queda en el día en que de verdad se vendió.

/// Qué parte del total cubre la seña y qué queda por cobrar o devolver.
class AplicacionSena {
  const AplicacionSena({required this.aplicadaCentavos, required this.aCobrarCentavos, required this.aDevolverCentavos});

  /// Lo que se descuenta del total (va como pago de la venta, sin tocar la caja).
  final int aplicadaCentavos;

  /// Lo que todavía hay que cobrarle al cliente.
  final int aCobrarCentavos;

  /// Si la seña superó el total (bajó un precio desde que se señó), la diferencia vuelve al cliente.
  final int aDevolverCentavos;
}

/// Reparte [senaCentavos] sobre el [totalCentavos] de la venta de entrega.
AplicacionSena aplicarSena({required int totalCentavos, required int senaCentavos}) {
  if (senaCentavos < 0) throw ArgumentError('La seña no puede ser negativa');
  final aplicada = senaCentavos < totalCentavos ? senaCentavos : totalCentavos;
  return AplicacionSena(
    aplicadaCentavos: aplicada,
    aCobrarCentavos: totalCentavos - aplicada,
    aDevolverCentavos: senaCentavos - aplicada,
  );
}

/// Null si la seña se puede tomar; si no, el motivo en palabras del dueño. [estimadoCentavos] es lo que vale hoy lo apartado:
/// una seña mayor sería devolver plata por adelantado.
String? validarSenaNueva({required int senaCentavos, required int estimadoCentavos}) {
  if (senaCentavos < 0) return 'La seña no puede ser negativa';
  if (senaCentavos > estimadoCentavos) return 'La seña no puede ser más que lo que vale el encargue';
  return null;
}

enum CajaDeSena { cajon, mercadoPago }

/// En qué caja entra (y de cuál sale si se devuelve) una seña.
CajaDeSena cajaDeLaSena({required bool esEfectivo}) => esEfectivo ? CajaDeSena.cajon : CajaDeSena.mercadoPago;
