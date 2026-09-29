// Productos pesables (fiambres, Mazzota). Se cargan en gramos, escribiendo
// "200 queso barra" (Regla 7). El stock se lleva en gramos, no en unidades.

/// Subtotal en centavos de una línea pesable: montoPorKiloCentavos × gramos
/// / 1000, con redondeo aritmético normal al centavo.
///
/// No redondea al peso entero: eso es responsabilidad del total final de la
/// venta (`redondeo`), y encadenar dos redondeos (acá y en el total) haría
/// que la suma de las líneas ya no coincida con lo que se cobra.
///
/// Único punto de esta multiplicación (Regla 7: "si esa multiplicación vive
/// en dos lados, tarde o temprano alguien mezcla precio por kilo con
/// cantidad en unidades"). Sirve tanto para el precio de venta como para el
/// costo-foto (Regla 4): quien necesite el costo de una línea pesable llama
/// a esta misma función con el costo por kilo en vez del precio.
int subtotalPesable({required int? montoPorKiloCentavos, required int gramos}) {
  if (montoPorKiloCentavos == null) {
    throw StateError('Pesable sin precio/costo por kilo cargado');
  }
  return (montoPorKiloCentavos * gramos / 1000).round();
}

/// Stock en gramos después de vender [gramosVendidos].
///
/// Puede quedar negativo: el stock informa, nunca bloquea (Regla 8). No es
/// un error, es el estado esperado hasta el próximo conteo físico.
int stockGramosPosterior({
  required int stockGramosAnterior,
  required int gramosVendidos,
}) {
  return stockGramosAnterior - gramosVendidos;
}
