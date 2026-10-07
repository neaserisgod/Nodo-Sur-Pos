// Faltantes del cierre que hay que explicar (El dueño, 2026-10-07: "vendo mucho pero no tengo un peso"). Revisando su
// base se vio que la ganancia de la app no mentía: lo que faltaba era ~$1.590.000 que salió de las cajas sin anotarse
// (casi todo de Mercado Pago: alquiler, luz, proveedores y gastos personales pagados desde la cuenta del negocio).
// Mientras eso no se anota, Equilibrio muestra como "retirable" plata que ya no existe. Por eso el cierre pregunta a
// dónde fue cada faltante, en el momento en que todavía se acuerda.
//
// Puro: sin Flutter, sin base.

enum CajaDelCierre { efectivo, mercadoPago, lata }

/// Valor de entrada del mínimo desde el que se pregunta (configurable, Configuración → Caja y cobros). Debajo no se
/// pregunta: en Mercado Pago la diferencia diaria es casi siempre la comisión (en la base real de La Plazoleta, de $400
/// a $5.300 por día), y preguntar por eso todos los días sería ruido. Configurable porque esa comisión depende de cuánto
/// venda cada comercio.
const umbralFaltantePorDefectoCentavos = 600000;

/// Lo que falta en cada caja (en positivo) a partir de las diferencias del cierre (contado − esperado), solo donde
/// falta al menos [umbral]. Una diferencia null es una caja que todavía no se contó: no se pregunta por ella. Los
/// sobrantes no se preguntan acá: no hay salida que explicar.
Map<CajaDelCierre, int> faltantesPorExplicar({
  required int diferenciaEfectivoCentavos,
  required int? diferenciaMpCentavos,
  required int? diferenciaLataCentavos,
  required int umbral,
}) {
  final resultado = <CajaDelCierre, int>{};
  void ver(CajaDelCierre caja, int? diferencia) {
    if (diferencia != null && -diferencia >= umbral) resultado[caja] = -diferencia;
  }

  ver(CajaDelCierre.efectivo, diferenciaEfectivoCentavos);
  ver(CajaDelCierre.mercadoPago, diferenciaMpCentavos);
  ver(CajaDelCierre.lata, diferenciaLataCentavos);
  return resultado;
}
