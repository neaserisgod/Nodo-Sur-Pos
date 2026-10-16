// Precios de todo el catálogo de una vez (El dueño, 2026-10-16: "subirle un porcentaje general a todos los precios y ver cuál
// es el porcentaje promedio sin tener en cuenta los cigarrillos, estandarizarlo todo"). Dos acciones y un número:
//  - la ganancia promedio (sobre el precio, Regla 14: la app no habla de markup) de los productos con costo;
//  - subir todos los precios X % (`aplicarAjustePrecio`, la misma fórmula que la edición en lote);
//  - igualar la ganancia: todos a X % sobre el precio (`precioConGananciaACentena`, la del porcentaje del proveedor).
// Los cigarrillos quedan siempre afuera (Regla 6: su ganancia es un monto fijo por atado). "Varios", promos, servicios e
// insumos ya no vienen en la lista de productos.

import 'ganancia.dart';

/// Lo que hace falta de un producto para estas cuentas. En un pesable, precio y costo son los del kilo.
typedef ProductoParaPrecios = ({int? precioCentavos, int? costoCentavos, bool esCigarrillo});

/// Entra en "subir todo": no es cigarrillo y tiene precio.
bool entraEnSubaGeneral(ProductoParaPrecios p) => !p.esCigarrillo && (p.precioCentavos ?? 0) > 0;

/// Entra en "igualar la ganancia": no es cigarrillo y tiene costo (sin costo no hay de dónde sacar el precio).
bool entraEnIgualarGanancia(ProductoParaPrecios p) => !p.esCigarrillo && (p.costoCentavos ?? 0) > 0;

/// La ganancia promedio sobre el precio, en basis points, de los productos con costo y precio (sin cigarrillos), y de cuántos
/// productos sale. Promedio simple: cada producto pesa lo mismo, venda mucho o poco. Null si no hay ninguno.
({int gananciaBp, int productos})? gananciaPromedio(Iterable<ProductoParaPrecios> productos) {
  var suma = 0;
  var n = 0;
  for (final p in productos) {
    final precio = p.precioCentavos ?? 0, costo = p.costoCentavos ?? 0;
    if (p.esCigarrillo || precio <= 0 || costo <= 0) continue;
    suma += gananciaBpDesdeCostoYPrecio(costo, precio);
    n++;
  }
  return n == 0 ? null : (gananciaBp: (suma / n).round(), productos: n);
}

/// El precio que le queda a un producto al igualar la ganancia a [gananciaBp]. Null si no entra.
int? precioAlIgualarGanancia(ProductoParaPrecios p, int gananciaBp) =>
    entraEnIgualarGanancia(p) ? precioConGananciaACentena(p.costoCentavos!, gananciaBp) : null;
