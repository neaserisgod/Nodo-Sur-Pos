// Cuentas de las promos (El dueño, 2026-09-29). Funciones puras: cómo se reparte
// lo que cuesta una promo entre sus artículos al cobrarla, y cuántas promos
// alcanzan con el stock que hay.

/// Reparte [totalCentavos] entre partes en proporción a [pesos], sin perder ni
/// inventar un centavo: la suma del resultado es siempre [totalCentavos]. Lo
/// que no entra exacto en la división se reparte de a un centavo desde la
/// primera parte.
///
/// La usa la venta de una promo: el precio de la promo se reparte entre sus
/// artículos según su precio de lista, así cada artículo lleva su parte y la
/// suma de las líneas da exactamente lo cobrado. Con pesos que suman 0 (nada
/// tiene precio de lista) reparte parejo.
List<int> repartirEnProporcion(int totalCentavos, List<int> pesos) {
  if (pesos.isEmpty) return const [];
  final sumaPesos = pesos.fold<int>(0, (a, p) => a + p);
  final partes = sumaPesos <= 0
      ? List<int>.filled(pesos.length, totalCentavos ~/ pesos.length)
      : [for (final p in pesos) totalCentavos * p ~/ sumaPesos];
  var resto = totalCentavos - partes.fold<int>(0, (a, p) => a + p);
  for (var i = 0; resto > 0 && i < partes.length; i++, resto--) {
    partes[i] += 1;
  }
  return partes;
}

/// Divide [totalCentavos] entre [cantidad] unidades con precio entero por
/// unidad: una o dos tandas (`r` unidades a un centavo más, el resto al
/// precio base), tal que `Σ cantidad × precio == totalCentavos` exacto.
List<({int cantidad, int precioUnitarioCentavos})> dividirEnUnidades(int totalCentavos, int cantidad) {
  if (cantidad <= 0) throw ArgumentError('La cantidad tiene que ser mayor a 0');
  final base = totalCentavos ~/ cantidad;
  final resto = totalCentavos - base * cantidad;
  return [
    if (resto > 0) (cantidad: resto, precioUnitarioCentavos: base + 1),
    if (cantidad - resto > 0) (cantidad: cantidad - resto, precioUnitarioCentavos: base),
  ];
}

/// Cuántas promos se pueden armar con el stock actual: el mínimo, entre sus
/// artículos, de `stock ~/ unidades por promo`. Nunca negativo (un artículo
/// con stock negativo deja la promo en 0). Sin artículos, 0.
int stockDePromo(List<({int stock, int cantidadPorPromo})> componentes) {
  if (componentes.isEmpty) return 0;
  var minimo = 1 << 30;
  for (final c in componentes) {
    // Un artículo sin cantidad por promo (dato roto) deja la promo en 0 en vez
    // de dividir por cero.
    final alcanza = c.stock <= 0 || c.cantidadPorPromo <= 0 ? 0 : c.stock ~/ c.cantidadPorPromo;
    if (alcanza < minimo) minimo = alcanza;
  }
  return minimo;
}

/// Los porcentajes de ganancia que el creador de promos ofrece con un toque (PC y celular); "Otro %" para el resto.
const atajosPorcentajePromo = [1500, 2000, 2500, 3000, 3500, 4000];

/// Porcentaje de partida al armar una promo a mano.
const porcentajePromoPorDefectoBp = 3000;

/// "30%", "12.5%".
String textoPorcentajeBp(int bp) => '${bp % 100 == 0 ? bp ~/ 100 : (bp / 100).toStringAsFixed(1)}%';
