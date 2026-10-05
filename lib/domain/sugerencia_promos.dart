// Qué promos conviene armar (El dueño, 2026-10-05: sugerir promos dentro del sistema). Funciones puras: encuentran los pares
// de productos que la gente ya se lleva juntos y proponen un porcentaje. El PRECIO no se calcula acá — lo decide
// `precioDePromo` (Regla 3: una sola fórmula); esto solo elige candidatos.

/// Dos productos que se llevan juntos. [productoA] < [productoB] siempre, para que el par no aparezca dos veces al revés.
class ParSugerido {
  const ParSugerido({
    required this.productoA,
    required this.productoB,
    required this.ventasJuntos,
    required this.ventasA,
    required this.ventasB,
    required this.liftBp,
  });

  final int productoA;
  final int productoB;

  /// Ventas que llevaron los dos.
  final int ventasJuntos;
  final int ventasA;
  final int ventasB;

  /// Cuánto más seguido van juntos que lo que daría el azar, en puntos básicos: 10000 = igual que el azar, 20000 = el
  /// doble de seguido. Sin esto, lo que se vende en casi todas las ventas (una gaseosa) "va junto" con cualquier cosa.
  final int liftBp;
}

/// Una venta con más productos distintos que esto es un pedido grande, no lo que lleva un cliente al mostrador: no cuenta
/// (y dispararía las combinaciones — 60 productos son 1.770 pares).
const maximoProductosPorVentaParaPares = 40;

/// Los pares que más se compran juntos, de [ventas] (cada una, los ids de producto distintos que llevó; ya sin anuladas).
///
/// - [elegibles]: solo estos ids pueden formar un par (null = todos). Sí cuentan para el total de ventas todas.
/// - [minVentasJuntos]: con menos de estas ventas en común, es casualidad.
/// - [liftMinimoBp]: ver [ParSugerido.liftBp]; 12000 = al menos 20 % más seguido que el azar.
/// - [promosExistentes]: los ids de cada promo ya armada; un par que ya entra entero en alguna no se vuelve a sugerir.
///
/// Orden: más ventas juntas primero; a igual cantidad, más lift; a igual lift, ids menores (para que sea determinista).
List<ParSugerido> paresQueSeCompranJuntos(
  List<Set<int>> ventas, {
  Set<int>? elegibles,
  int minVentasJuntos = 3,
  int liftMinimoBp = 12000,
  int maximo = 10,
  List<Set<int>> promosExistentes = const [],
}) {
  final ventasPorProducto = <int, int>{};
  final ventasPorPar = <(int, int), int>{};
  var total = 0;

  for (final venta in ventas) {
    if (venta.length > maximoProductosPorVentaParaPares) continue;
    total++;
    for (final id in venta) {
      ventasPorProducto[id] = (ventasPorProducto[id] ?? 0) + 1;
    }
    final ids = [
      for (final id in venta)
        if (elegibles == null || elegibles.contains(id)) id,
    ]..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final par = (ids[i], ids[j]);
        ventasPorPar[par] = (ventasPorPar[par] ?? 0) + 1;
      }
    }
  }

  final pares = <ParSugerido>[];
  ventasPorPar.forEach((par, juntos) {
    if (juntos < minVentasJuntos) return;
    final (a, b) = par;
    if (promosExistentes.any((p) => p.contains(a) && p.contains(b))) return;
    final ventasA = ventasPorProducto[a]!;
    final ventasB = ventasPorProducto[b]!;
    final liftBp = juntos * total * 10000 ~/ (ventasA * ventasB);
    if (liftBp < liftMinimoBp) return;
    pares.add(
      ParSugerido(
        productoA: a,
        productoB: b,
        ventasJuntos: juntos,
        ventasA: ventasA,
        ventasB: ventasB,
        liftBp: liftBp,
      ),
    );
  });

  pares.sort((x, y) {
    final porJuntos = y.ventasJuntos.compareTo(x.ventasJuntos);
    if (porJuntos != 0) return porJuntos;
    final porLift = y.liftBp.compareTo(x.liftBp);
    if (porLift != 0) return porLift;
    final porA = x.productoA.compareTo(y.productoA);
    return porA != 0 ? porA : x.productoB.compareTo(y.productoB);
  });
  return pares.take(maximo).toList();
}

/// El porcentaje de ganancia con que arrancar una promo de artículos que cuestan [costoCentavos] y valen
/// [precioListaCentavos] sueltos: regala más o menos la mitad de la ganancia de los sueltos, en saltos de 5 %, entre 10 % y
/// 40 % (las opciones del creador de promos). Null si los sueltos no dejan ganancia suficiente para que valga la pena
/// descontar (menos de 20 %): ahí una promo ya sería casi sin ganancia.
///
/// Es solo el punto de partida — el creador de promos deja cambiarlo.
int? porcentajeSugeridoDePromoBp({
  required int costoCentavos,
  required int precioListaCentavos,
}) {
  if (precioListaCentavos <= 0 ||
      costoCentavos <= 0 ||
      costoCentavos >= precioListaCentavos) {
    return null;
  }
  final margenBp =
      (precioListaCentavos - costoCentavos) * 10000 ~/ precioListaCentavos;
  final mitad = margenBp ~/ 2 ~/ 500 * 500;
  if (mitad < 1000) return null;
  return mitad > 4000 ? 4000 : mitad;
}
