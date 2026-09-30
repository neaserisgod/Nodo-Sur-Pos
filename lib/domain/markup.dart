// Triángulo costo-precio-markup. Todos los montos en centavos (Int).
// Porcentajes en basis points (bp): 7000 bp = 70,00%, 500 bp = 5,00%.
//
// El precio se carga a mano y la app no sugiere ni aplica markup
// automáticamente (Regla 14). Por eso este módulo no elige ni completa un
// precio o costo por sí solo: son conversiones puras del triángulo,
// disponibles para quien las necesite (p. ej. el margen en vivo mientras se
// escribe el precio), nunca disparadas para autocompletar un campo.

import 'dinero.dart';

/// precio = costo × (1 + markupBp / 10000), redondeado hacia arriba al peso
/// entero (Regla 1: el negocio no maneja centavos).
int precioDesdeCostoYMarkup(int costoCentavos, int markupBp) {
  if (markupBp <= -10000) {
    throw ArgumentError('markupBp no puede ser ≤ -10000 (división por cero)');
  }
  final numerador = costoCentavos * (10000 + markupBp);
  return redondearFraccionHaciaArriba(numerador, 10000, centavosPorPeso);
}

/// costo = precio / (1 + markupBp / 10000), redondeado hacia arriba al peso
/// entero (Regla 1).
int costoDesdePrecioYMarkup(int precioCentavos, int markupBp) {
  if (markupBp <= -10000) {
    throw ArgumentError('markupBp no puede ser ≤ -10000 (división por cero)');
  }
  final numerador = precioCentavos * 10000;
  return redondearFraccionHaciaArriba(numerador, 10000 + markupBp, centavosPorPeso);
}

/// markup en basis points a partir de costo y precio: (precio − costo) / costo.
///
/// Es el "margen en vivo" de Regla 14: mientras se escribe el precio, se
/// recalcula con el costo ya cargado del producto. Puede dar negativo — eso
/// es intencional (Regla 5: un aumento de costo que el precio todavía no
/// absorbió tiene que verse, no ocultarse).
///
/// Un costo en 0 lanza error en vez de devolver un margen infinito: un
/// producto sin costo cargado es un dato faltante, no un cero silencioso.
int markupBpDesdeCostoYPrecio(int costoCentavos, int precioCentavos) {
  if (costoCentavos == 0) {
    throw ArgumentError('costoCentavos no puede ser 0 para calcular markup');
  }
  return ((precioCentavos - costoCentavos) * 10000 / costoCentavos).round();
}

/// Ganancia bruta de una línea de venta, a partir de los valores-foto de
/// precio y costo (Regla 4): (precioUnitario − costoUnitario) × cantidad.
int gananciaBruta(
  int precioUnitarioCentavos,
  int costoUnitarioCentavos,
  int cantidad,
) {
  return (precioUnitarioCentavos - costoUnitarioCentavos) * cantidad;
}

/// Un múltiplo de $100 en centavos: el paso al que se redondea un precio
/// calculado con el porcentaje del proveedor.
const int centavosPorCentena = 10000;

/// Precio de venta = costo + [markupBp], redondeado hacia arriba a la
/// PRÓXIMA CENTENA de pesos (El dueño, 2026-09-29: "un selector de porcentaje
/// por proveedor + redondeo para arriba a la próxima centena"). Ej.: costo
/// $1.030 con 30% = $1.339 → $1.400; un resultado que ya cae justo en centena
/// no sube ($1.000 con 30% = $1.300).
///
/// Es el único cálculo del precio automático por proveedor (Regla 3). Se hace
/// en una sola operación exacta con enteros (`redondearFraccionHaciaArriba`),
/// sin pasar por un redondeo intermedio al peso. No aplica a los cigarrillos:
/// su ganancia es un monto fijo por atado (Regla 6), no un porcentaje.
int precioConMarkupACentena(int costoCentavos, int markupBp) {
  if (markupBp <= -10000) {
    throw ArgumentError('markupBp no puede ser ≤ -10000');
  }
  final numerador = costoCentavos * (10000 + markupBp);
  return redondearFraccionHaciaArriba(numerador, 10000, centavosPorCentena);
}

/// Precio de una promo (El dueño, 2026-09-29: "se carga precio costo de 2 o más
/// artículos, se le suma el porcentaje, y no se tiene que pasar del precio
/// de lista normal"). Costo total de los artículos + [markupBp], redondeado a
/// la próxima centena como cualquier precio por porcentaje
/// (`precioConMarkupACentena`) — y con TOPE en la suma de los precios de
/// lista: una promo nunca cuesta más que llevar los artículos sueltos.
///
/// [topeadoPorLista] avisa que el tope fue lo que decidió el precio (el
/// porcentaje pedía más). El tope se aplica DESPUÉS del redondeo: una promo
/// que redondeada pasaría de la lista queda en la lista.
({int precioCentavos, bool topeadoPorLista}) precioDePromo({
  required int costoTotalCentavos,
  required int precioListaTotalCentavos,
  required int markupBp,
}) {
  final calculado = precioConMarkupACentena(costoTotalCentavos, markupBp);
  if (calculado > precioListaTotalCentavos) {
    return (precioCentavos: precioListaTotalCentavos, topeadoPorLista: true);
  }
  return (precioCentavos: calculado, topeadoPorLista: false);
}
