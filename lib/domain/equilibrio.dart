// Punto de equilibrio y ganancia neta del mes (Regla 12). Todos los montos
// en centavos.
//
// A diferencia del sistema anterior, acá no se descuenta una comisión por
// medio de pago: la comisión de Mercado Pago de este negocio es un monto fijo
// mensual (se suma a los gastos fijos), no un porcentaje por transacción.

import 'reposicion.dart';

class ResultadoGananciaBruta {
  /// Suma de (precio − costo) de cada línea con costo conocido. A diferencia
  /// de `calcularReposicion`, acá los cigarrillos SÍ entran: su costo-foto es
  /// lo que se le paga a Distribuidora, y la diferencia contra el precio de venta es
  /// ganancia real, aunque la lata la administre por su cuenta (Regla 6). Lo
  /// que `reposicion.dart` excluye es la reposición de esa plata, no la
  /// ganancia que representa.
  final int gananciaBrutaCentavos;

  /// Venta de las líneas con costo conocido — el denominador del margen
  /// ponderado, no la venta total del período.
  final int ventaConCostoCentavos;

  /// Igual concepto que en `reposicion.dart`: "Varios" y alta rápida
  /// pendiente de completar no aportan ganancia calculable, así que no se
  /// inventa un costo 0 para ellos — se reportan aparte.
  final int vendidoSinCostoCentavos;

  const ResultadoGananciaBruta({
    required this.gananciaBrutaCentavos,
    required this.ventaConCostoCentavos,
    required this.vendidoSinCostoCentavos,
  });

  /// Fracción (0.30 = 30%), no porcentaje entero: se mueve solo según qué se
  /// vendió (Regla 12, "margen ponderado real"), nunca un número asumido.
  /// Null si no hubo nada vendido con costo conocido en el período — no hay
  /// nada que ponderar, y un 0 acá se leería como "margen nulo", que sería
  /// engañoso.
  double? get margenPonderado =>
      ventaConCostoCentavos == 0 ? null : gananciaBrutaCentavos / ventaConCostoCentavos;
}

/// Reconstruye la ganancia real de un conjunto de líneas de venta (Regla 12).
/// Recibe el mismo tipo que `calcularReposicion` para no duplicar cómo se
/// arma una línea desde la base (eso vive en la capa de datos).
ResultadoGananciaBruta calcularGananciaBruta({required List<LineaParaReposicion> lineas}) {
  var ganancia = 0;
  var ventaConCosto = 0;
  var sinCosto = 0;

  for (final linea in lineas) {
    final costo = linea.costoLineaCentavos;
    if (costo == null) {
      sinCosto += linea.precioLineaCentavos;
      continue;
    }
    ganancia += linea.precioLineaCentavos - costo;
    ventaConCosto += linea.precioLineaCentavos;
  }

  return ResultadoGananciaBruta(
    gananciaBrutaCentavos: ganancia,
    ventaConCostoCentavos: ventaConCosto,
    vendidoSinCostoCentavos: sinCosto,
  );
}

/// Venta diaria necesaria para cubrir los fijos, con el margen REAL del
/// período (Regla 12) — nunca un porcentaje fijo asumido, porque un mix de
/// venta distinto da un punto de equilibrio distinto.
///
/// Null si el margen no es positivo: con margen 0 o negativo ningún volumen
/// de venta alcanza a cubrir los fijos, así que no hay un número que devolver
/// sin que sea engañoso.
int? ventaDiariaDeEquilibrio({
  required int fijosMensualesCentavos,
  required double margenPonderado,
  int diasDelMes = 30,
}) {
  if (margenPonderado <= 0 || diasDelMes <= 0) return null;
  final ventaMensual = fijosMensualesCentavos / margenPonderado;
  return (ventaMensual / diasDelMes).round();
}

class ResultadoEquilibrio {
  final int gastosFijosCentavos;
  final int gananciaBrutaCentavos;

  /// Ganancia neta = ganancia bruta − gastos fijos. Negativa si todavía no
  /// se cubrió el mes.
  final int gananciaNetaCentavos;

  /// 0 a 100: porcentaje de los gastos fijos ya cubiertos por la ganancia
  /// bruta del mes. No pasa de 100 aunque la ganancia supere los fijos.
  final int pctAvance;

  /// Cuánto falta para cubrir los gastos fijos. 0 si ya se cubrió.
  final int faltanteCentavos;

  final bool cubierto;

  const ResultadoEquilibrio({
    required this.gastosFijosCentavos,
    required this.gananciaBrutaCentavos,
    required this.gananciaNetaCentavos,
    required this.pctAvance,
    required this.faltanteCentavos,
    required this.cubierto,
  });
}

ResultadoEquilibrio calcularEquilibrio({
  required int gastosFijosCentavos,
  required int gananciaBrutaCentavos,
}) {
  final gananciaNeta = gananciaBrutaCentavos - gastosFijosCentavos;

  final pctAvance = gastosFijosCentavos == 0
      ? 100
      : ((gananciaBrutaCentavos / gastosFijosCentavos) * 100).round().clamp(0, 100);

  final faltante = gastosFijosCentavos - gananciaBrutaCentavos;

  return ResultadoEquilibrio(
    gastosFijosCentavos: gastosFijosCentavos,
    gananciaBrutaCentavos: gananciaBrutaCentavos,
    gananciaNetaCentavos: gananciaNeta,
    pctAvance: pctAvance,
    faltanteCentavos: faltante <= 0 ? 0 : faltante,
    cubierto: faltante <= 0,
  );
}

/// Reserva diaria de fijos = fijos del mes ÷ días del mes (Regla 12): cuánto
/// margen tenía que generar hoy para ir al ritmo del mes. Es puramente
/// informativa — no entra en ninguna fórmula de caja (Regla 10) ni de
/// arqueo, se muestra solo como indicador en el cierre.
///
/// Conectada con datos reales desde la fase 7: `repositorio_cierre.dart`
/// llama a esta función con los fijos reales del mes (`fijosDelMes()` en
/// `repositorio_equilibrio.dart`), no con un valor configurable. La columna
/// `configuracion.reservaDiariaFijosCentavos` que existió como valor fijo
/// mientras esta conexión no existía quedó vestigial y sin leerse (ver su
/// propio comentario en `lib/data/tables/configuracion.dart`).
int reservaDiariaFijosCentavos({
  required int fijosMensualesCentavos,
  int diasDelMes = 30,
}) {
  if (diasDelMes <= 0) return 0;
  return (fijosMensualesCentavos / diasDelMes).round();
}

/// Estado de un gasto fijo en el mes (lista "Fijos del mes", mock v4).
enum EstadoFijo { pagado, pendiente, faltaCargar }

/// Sin monto cargado del mes no se puede saber si está pagado ("avisar antes que inventar"): falta cargar. Con monto,
/// pagado si lo pagado lo cubre.
EstadoFijo estadoDelFijo({required int? montoCentavos, required int pagadoCentavos}) {
  if (montoCentavos == null) return EstadoFijo.faltaCargar;
  return pagadoCentavos >= montoCentavos ? EstadoFijo.pagado : EstadoFijo.pendiente;
}

/// Días que faltan para que venza un fijo este mes (0 = vence hoy, negativo = ya venció). Un [diaVencimiento] que el mes
/// no tiene (31 en septiembre, 30 en febrero) vence el último día del mes: el alquiler "el 31" no se saltea un mes.
int diasParaVencer({required int diaVencimiento, required DateTime hoy}) {
  final ultimoDia = DateTime(hoy.year, hoy.month + 1, 0).day;
  final dia = diaVencimiento.clamp(1, ultimoDia);
  // Por fecha de calendario, no por horas: a la noche del día 9 un vencimiento del 10 sigue siendo "mañana".
  return DateTime.utc(hoy.year, hoy.month, dia).difference(DateTime.utc(hoy.year, hoy.month, hoy.day)).inDays;
}
