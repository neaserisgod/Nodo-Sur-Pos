// Selector de período compartido entre Proveedores y Productos (fase 13):
// "vendido" y "ganancia" no se fijan a un período — un selector arriba de
// la lista decide desde cuándo se cuenta, igual en las dos pantallas
// (regla 5 del principio de fatiga visual: la misma cosa en el mismo
// lugar).

/// Nunca texto libre — mismo criterio que `mediosPagoProveedor` o
/// `motivosAjusteDeStock`: un enum, no un String suelto que se pueda
/// escribir mal.
enum PeriodoResumen { hoy, semana, mes, desdeUltimoPago }

/// Inicio del rango para [periodo], tomando [ahora] como "ahora" — nunca
/// `DateTime.now()` directo adentro de una función de dominio (mismo motivo
/// que el resto de la app: sin esto, un test no puede fijar el reloj).
///
/// Null significa "sin corte, desde siempre": el caso de
/// [PeriodoResumen.desdeUltimoPago] cuando [ultimoPago] es null (el
/// proveedor nunca recibió un pago) — la fila aclara "desde siempre" en vez
/// de mostrar una fecha que no existe.
DateTime? inicioDePeriodo(
  PeriodoResumen periodo,
  DateTime ahora, {
  DateTime? ultimoPago,
}) {
  final inicioDeHoy = DateTime(ahora.year, ahora.month, ahora.day);
  return switch (periodo) {
    PeriodoResumen.hoy => inicioDeHoy,
    // Lunes de la semana en curso — `DateTime.weekday` va de 1 (lunes) a 7
    // (domingo), así que restarle (weekday - 1) días a hoy siempre cae en
    // lunes.
    PeriodoResumen.semana => inicioDeHoy.subtract(
      Duration(days: ahora.weekday - 1),
    ),
    PeriodoResumen.mes => DateTime(ahora.year, ahora.month, 1),
    PeriodoResumen.desdeUltimoPago => ultimoPago,
  };
}

const _nombresDias = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];

/// "Pedir hoy" de la lista de Proveedores: el día de pedido es texto libre ("Martes", "martes", "Miércoles", "Miercoles"),
/// así que se compara sin mayúsculas ni acentos contra el día de [ahora].
bool tocaPedirHoy(String? diaPedido, DateTime ahora) {
  if (diaPedido == null) return false;
  final d = diaPedido.trim().toLowerCase().replaceAll('é', 'e').replaceAll('á', 'a');
  return d == _nombresDias[ahora.weekday - 1];
}
