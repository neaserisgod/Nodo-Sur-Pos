// Precios de todo el catálogo de una vez (El dueño, 2026-10-16: "subirle un porcentaje general a todos los precios y ver cuál
// es el porcentaje promedio sin tener en cuenta los cigarrillos, estandarizarlo todo"). Dos acciones y un número:
//  - la ganancia promedio (sobre el precio, Regla 14: la app no habla de markup) de los productos con costo;
//  - subir todos los precios X % (`aplicarAjustePrecio`, la misma fórmula que la edición en lote);
//  - igualar la ganancia: todos a X % sobre el precio (`precioConGananciaACentena`, la del porcentaje del proveedor).
// Quedan siempre afuera (no cuentan en el promedio ni se les toca el precio): los cigarrillos (Regla 6: su ganancia es un monto
// fijo por atado) y los fiambres (El dueño, 2026-10-16: "sin contar los fiambres también"), que son los que se venden por peso
// o los de la categoría Fiambres. "Varios", promos, servicios e insumos ya no vienen en la lista de productos.

import 'ganancia.dart';
import 'normalizacion_texto.dart';

/// Lo que hace falta de un producto para estas cuentas. [afuera]: cigarrillo o fiambre (ver [productoParaPrecios]).
typedef ProductoParaPrecios = ({int? precioCentavos, int? costoCentavos, bool afuera});

/// Un fiambre: se vende por peso o está en la categoría Fiambres (con o sin mayúsculas, "fiambre" o "fiambres").
bool esFiambre({required bool esPesable, String? nombreCategoria}) =>
    esPesable || (nombreCategoria != null && normalizarTexto(nombreCategoria).trim().startsWith('fiambre'));

/// Arma el producto para estas cuentas: la única definición de quién queda afuera (Regla 3).
ProductoParaPrecios productoParaPrecios({
  required int? precioCentavos,
  required int? costoCentavos,
  required String tipoCigarrillo,
  required bool esPesable,
  String? nombreCategoria,
}) =>
    (
      precioCentavos: precioCentavos,
      costoCentavos: costoCentavos,
      afuera: tipoCigarrillo != 'ninguno' || esFiambre(esPesable: esPesable, nombreCategoria: nombreCategoria),
    );

/// Entra en "subir todo": no queda afuera y tiene precio.
bool entraEnSubaGeneral(ProductoParaPrecios p) => !p.afuera && (p.precioCentavos ?? 0) > 0;

/// Entra en "igualar la ganancia": no queda afuera y tiene costo (sin costo no hay de dónde sacar el precio).
bool entraEnIgualarGanancia(ProductoParaPrecios p) => !p.afuera && (p.costoCentavos ?? 0) > 0;

/// La ganancia promedio sobre el precio, en basis points, de los productos con costo y precio (sin los que quedan afuera), y de cuántos
/// productos sale. Promedio simple: cada producto pesa lo mismo, venda mucho o poco. Null si no hay ninguno.
({int gananciaBp, int productos})? gananciaPromedio(Iterable<ProductoParaPrecios> productos) {
  var suma = 0;
  var n = 0;
  for (final p in productos) {
    final precio = p.precioCentavos ?? 0, costo = p.costoCentavos ?? 0;
    if (p.afuera || precio <= 0 || costo <= 0) continue;
    suma += gananciaBpDesdeCostoYPrecio(costo, precio);
    n++;
  }
  return n == 0 ? null : (gananciaBp: (suma / n).round(), productos: n);
}

/// El precio que le queda a un producto al igualar la ganancia a [gananciaBp]. Null si no entra.
int? precioAlIgualarGanancia(ProductoParaPrecios p, int gananciaBp) =>
    entraEnIgualarGanancia(p) ? precioConGananciaACentena(p.costoCentavos!, gananciaBp) : null;
