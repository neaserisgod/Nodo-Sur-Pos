// Precios de todo el catálogo de una vez (El dueño, 2026-10-16: "subirle un porcentaje general a todos los precios y ver cuál
// es el porcentaje promedio sin tener en cuenta los cigarrillos, estandarizarlo todo").
//
// El dueño piensa los precios en MARKUP, sobre el costo (mismo día, después de probar la primera versión que subía sobre el
// precio: "el cálculo de suba se hace sobre el precio costo"; "si a sale 100, le sumo un markup del 70 para que me dé ganancia de
// 42 aprox"). Por eso acá todo se dice en markup:
//  - el markup promedio (y la ganancia sobre el precio que da, entre paréntesis) de los productos con costo;
//  - subir todo X %: el markup sube X puntos, o sea al precio se le suma el X % del costo ($7.000 con costo $6.000 y X = 15 →
//    $7.900);
//  - igualar el markup a X %: precio = costo × (1 + X), por el mismo camino que el porcentaje del proveedor (que se guarda como
//    ganancia sobre el precio: X / (1 + X)), redondeado a la centena.
// Quedan siempre afuera (no cuentan en el promedio ni se les toca el precio): los cigarrillos (Regla 6: su ganancia es un monto
// fijo por atado) y los fiambres (El dueño, 2026-10-16: "sin contar los fiambres también"), que son los que se venden por peso
// o los de la categoría Fiambres. "Varios", promos, servicios e insumos ya no vienen en la lista de productos.

import 'dinero.dart' show centavosPorPeso;
import 'edicion_masiva_precios.dart';
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

/// Entra en "subir todo": no queda afuera y tiene precio y costo (la suba es un porcentaje del costo).
bool entraEnSubaGeneral(ProductoParaPrecios p) => !p.afuera && (p.precioCentavos ?? 0) > 0 && (p.costoCentavos ?? 0) > 0;

/// Entra en "solo redondear": no queda afuera y tiene precio.
bool entraEnRedondeo(ProductoParaPrecios p) => !p.afuera && (p.precioCentavos ?? 0) > 0;

/// Entra en "igualar la ganancia": no queda afuera y tiene costo (sin costo no hay de dónde sacar el precio).
bool entraEnIgualarGanancia(ProductoParaPrecios p) => !p.afuera && (p.costoCentavos ?? 0) > 0;

/// El markup promedio (sobre el costo) y la ganancia sobre el precio que da, en basis points, de los productos con costo y precio
/// (sin los que quedan afuera), y de cuántos productos sale. Promedio simple: cada producto pesa lo mismo. Null si no hay ninguno.
({int markupBp, int gananciaBp, int productos})? promedioDePrecios(Iterable<ProductoParaPrecios> productos) {
  var sumaMarkup = 0, sumaGanancia = 0, n = 0;
  for (final p in productos) {
    final precio = p.precioCentavos ?? 0, costo = p.costoCentavos ?? 0;
    if (p.afuera || precio <= 0 || costo <= 0) continue;
    sumaMarkup += ((precio - costo) * 10000 / costo).round();
    sumaGanancia += gananciaBpDesdeCostoYPrecio(costo, precio);
    n++;
  }
  return n == 0 ? null : (markupBp: (sumaMarkup / n).round(), gananciaBp: (sumaGanancia / n).round(), productos: n);
}

/// La ganancia sobre el precio que da un markup: m / (1 + m). Un markup de 70 % da 41,2 %.
// Hacia abajo: redondeada para arriba, la ganancia daría un precio apenas mayor y la centena saltaría a la siguiente
// (markup 70 % con costo $1.000 daba $1.800 en vez de $1.700).
int gananciaBpDesdeMarkupBp(int markupBp) => markupBp * 10000 ~/ (10000 + markupBp);

/// "Subir todo X %": al precio se le suman [puntosBp] del costo (el markup sube esos puntos), redondeado hacia arriba al peso.
/// Null si el producto no entra.
int? precioAlSubirSobreCosto(ProductoParaPrecios p, int puntosBp, {int redondeoCentavos = centavosPorPeso}) => entraEnSubaGeneral(p)
    ? aplicarAjustePrecio(
        precioActualCentavos: p.precioCentavos!,
        tipo: TipoAjustePrecio.sumarPorcentajeDelCosto,
        valor: puntosBp,
        costoCentavos: p.costoCentavos,
        redondeoCentavos: redondeoCentavos,
      )
    : null;

/// El precio que le queda a un producto al igualar el markup a [markupBp] (por el porcentaje del proveedor, a la centena). Null si
/// no entra.
int? precioAlIgualarMarkup(ProductoParaPrecios p, int markupBp) =>
    entraEnIgualarGanancia(p) ? precioConGananciaACentena(p.costoCentavos!, gananciaBpDesdeMarkupBp(markupBp)) : null;

/// Un cambio de precio que dejó el historial (`historial_de_precios`: cada fila es la foto DESPUÉS del cambio).
typedef FotoDePrecio = ({int id, int productoId, DateTime fecha});

/// Las fotos de la última suba general, para deshacerla: el último minuto con al menos [minimo] cambios (una suba toca muchos
/// productos a la vez; un precio corregido a mano después es uno solo y no se confunde con ella). Cada producto aparece una vez
/// (su foto más vieja de ese lote: la de la suba). Vacío si no hay ninguna.
List<FotoDePrecio> loteDeLaUltimaSuba(List<FotoDePrecio> fotos, {int minimo = 5}) {
  final porMinuto = <DateTime, List<FotoDePrecio>>{};
  for (final f in fotos) {
    final m = DateTime(f.fecha.year, f.fecha.month, f.fecha.day, f.fecha.hour, f.fecha.minute);
    (porMinuto[m] ??= []).add(f);
  }
  final minutos = porMinuto.keys.toList()..sort();
  for (final m in minutos.reversed) {
    // La transacción puede cruzar el cambio de minuto: se junta con el minuto anterior.
    final lote = [...porMinuto[m]!, ...?porMinuto[m.subtract(const Duration(minutes: 1))]];
    final porProducto = <int, FotoDePrecio>{};
    for (final f in lote) {
      final ya = porProducto[f.productoId];
      // La más VIEJA del lote es la de la suba: una corrección a mano en el mismo minuto viene después.
      if (ya == null || f.id < ya.id) porProducto[f.productoId] = f;
    }
    if (porProducto.length >= minimo) return porProducto.values.toList();
  }
  return const [];
}
