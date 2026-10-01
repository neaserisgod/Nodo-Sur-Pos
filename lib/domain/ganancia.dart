// Triángulo costo-precio-ganancia. Todos los montos en centavos (Int).
// Porcentajes en basis points (bp): 3000 bp = 30,00%, 500 bp = 5,00%.
//
// La ganancia es SOBRE EL PRECIO DE VENTA, no sobre el costo:
//
//     ganancia % = (precio − costo) / precio
//     precio     = costo / (1 − ganancia %)
//
// Es la definición "real": 30% de ganancia significa que de cada $100 que
// entran, $30 son ganancia y $70 son reposición — el mismo criterio con el que
// el negocio mira el margen ponderado (REGLAS-NEGOCIO, equilibrio) y con el
// que la reposición separa el costo. Un recargo sobre el costo (markup) daría
// otro número para la misma venta (precio = costo × 1,30 → solo 23,08% de
// ganancia real) y se confunde fácil con la ganancia; por eso la app habla
// únicamente de ganancia. Un 100% de ganancia es imposible (el precio tendería
// a infinito): el tope es estrictamente menor a 10000 bp.
//
// El precio se carga a mano y la app no sugiere ni aplica ganancia
// automáticamente salvo el porcentaje por proveedor (Regla 3 / Regla 14). Este
// módulo no elige ni completa un precio o costo por sí solo: son conversiones
// puras del triángulo, nunca disparadas para autocompletar un campo.

import 'dinero.dart';

const int _cienPorCientoBp = 10000;

void _validarGananciaBp(int gananciaBp) {
  if (gananciaBp >= _cienPorCientoBp) {
    throw ArgumentError('gananciaBp tiene que ser menor a 10000 (100% de ganancia no existe)');
  }
}

/// precio = costo / (1 − gananciaBp / 10000), redondeado hacia arriba al peso
/// entero (Regla 1: el negocio no maneja centavos).
int precioDesdeCostoYGanancia(int costoCentavos, int gananciaBp) {
  _validarGananciaBp(gananciaBp);
  final numerador = costoCentavos * _cienPorCientoBp;
  return redondearFraccionHaciaArriba(numerador, _cienPorCientoBp - gananciaBp, centavosPorPeso);
}

/// costo = precio × (1 − gananciaBp / 10000), redondeado hacia arriba al peso
/// entero (Regla 1).
int costoDesdePrecioYGanancia(int precioCentavos, int gananciaBp) {
  _validarGananciaBp(gananciaBp);
  final numerador = precioCentavos * (_cienPorCientoBp - gananciaBp);
  return redondearFraccionHaciaArriba(numerador, _cienPorCientoBp, centavosPorPeso);
}

/// Ganancia en basis points a partir de costo y precio: (precio − costo) / precio.
///
/// Es la "ganancia en vivo" de Regla 14: mientras se escribe el precio, se
/// recalcula con el costo ya cargado del producto. Puede dar negativa — eso
/// es intencional (Regla 5: un aumento de costo que el precio todavía no
/// absorbió tiene que verse, no ocultarse).
///
/// Un precio en 0 lanza error en vez de devolver una ganancia infinita.
int gananciaBpDesdeCostoYPrecio(int costoCentavos, int precioCentavos) {
  if (precioCentavos == 0) {
    throw ArgumentError('precioCentavos no puede ser 0 para calcular la ganancia');
  }
  return ((precioCentavos - costoCentavos) * _cienPorCientoBp / precioCentavos).round();
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

/// Precio de venta con [gananciaBp] sobre el precio, redondeado hacia arriba a
/// la PRÓXIMA CENTENA de pesos (El dueño, 2026-09-29: "un selector de porcentaje
/// por proveedor + redondeo para arriba a la próxima centena"). Ej.: costo
/// $1.000 con 30% de ganancia = $1.428,57 → $1.500; un resultado que ya cae
/// justo en centena no sube ($700 con 30% = $1.000).
///
/// Es el único cálculo del precio automático por proveedor (Regla 3). Se hace
/// en una sola operación exacta con enteros (`redondearFraccionHaciaArriba`),
/// sin pasar por un redondeo intermedio al peso. No aplica a los cigarrillos:
/// su ganancia es un monto fijo por atado (Regla 6), no un porcentaje.
int precioConGananciaACentena(int costoCentavos, int gananciaBp) {
  _validarGananciaBp(gananciaBp);
  final numerador = costoCentavos * _cienPorCientoBp;
  return redondearFraccionHaciaArriba(numerador, _cienPorCientoBp - gananciaBp, centavosPorCentena);
}

/// Precio de una promo (El dueño, 2026-09-29: "se carga precio costo de 2 o más
/// artículos, se le aplica el porcentaje de ganancia, y no se tiene que pasar del precio
/// de lista normal"). Costo total de los artículos con [gananciaBp] de ganancia, redondeado a
/// la próxima centena como cualquier precio por porcentaje
/// (`precioConGananciaACentena`) — y con TOPE en la suma de los precios de
/// lista: una promo nunca cuesta más que llevar los artículos sueltos.
///
/// [topeadoPorLista] avisa que el tope fue lo que decidió el precio (el
/// porcentaje pedía más). El tope se aplica DESPUÉS del redondeo: una promo
/// que redondeada pasaría de la lista queda en la lista.
({int precioCentavos, bool topeadoPorLista}) precioDePromo({
  required int costoTotalCentavos,
  required int precioListaTotalCentavos,
  required int gananciaBp,
}) {
  final calculado = precioConGananciaACentena(costoTotalCentavos, gananciaBp);
  if (calculado > precioListaTotalCentavos) {
    return (precioCentavos: precioListaTotalCentavos, topeadoPorLista: true);
  }
  return (precioCentavos: calculado, topeadoPorLista: false);
}
