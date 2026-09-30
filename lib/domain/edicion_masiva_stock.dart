// Edición masiva de stock (El dueño, 2026-09-19: "editor masivo, ya sea de
// precios costo stock etc etc" — el ajuste masivo de precio/costo
// (`edicion_masiva_precios.dart`) ya existía; esto lo extiende a stock,
// pensado sobre todo para la companion (ej. recibir un pedido y sumarle
// unidades a varios productos de una).
//
// Fórmula propia, no una reutilización de `aplicarAjustePrecio`: esa
// trabaja en centavos y siempre redondea al peso entero, ninguna de las dos
// cosas aplica acá (stock son unidades o gramos enteros, sin redondeo de
// moneda). Tampoco tiene versión porcentual — "subir un 10% el stock" no es
// un pedido real de este negocio, a diferencia del precio.

/// Las tres formas de ajuste — mismo criterio que `TipoAjustePrecio`: sumar
/// y restar quedan separados para no inventar una convención de signo.
enum TipoAjusteStock { nuevoFijo, sumar, restar }

/// Calcula el stock nuevo de UN producto. [valor] son unidades o gramos
/// según corresponda al producto (`ajustarStockEnLote`, en
/// `data/repositorio_productos.dart`, decide cuál).
///
/// A diferencia de [aplicarAjustePrecio] (`edicion_masiva_precios.dart`),
/// el resultado puede dar negativo — Regla 8 de negocio: el stock informa,
/// nunca bloquea. Un ajuste masivo no es una excepción a esa regla.
int aplicarAjusteStock({
  required int actual,
  required TipoAjusteStock tipo,
  required int valor,
}) => switch (tipo) {
  TipoAjusteStock.nuevoFijo => valor,
  TipoAjusteStock.sumar => actual + valor,
  TipoAjusteStock.restar => actual - valor,
};
