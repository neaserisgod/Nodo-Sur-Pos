// Vuelto en efectivo: con cuánto paga el cliente y cuánto se le devuelve.
// Todo en centavos (Convención 1). Es solo orientación para quien cobra: el
// total de la venta ya viene redondeado (`redondeo.dart`) y el vuelto no se
// registra, la caja cuenta lo cobrado.

/// Billetes de uso común, de menor a mayor: $2.000, $5.000, $10.000, $20.000,
/// $50.000 y $100.000.
const _billetesCentavos = [200000, 500000, 1000000, 2000000, 5000000, 10000000];

/// Paso con el que se sigue ofreciendo cuando el total supera al billete más grande.
const _pasoSobreElMayorCentavos = 5000000;

/// Los [cuantos] primeros montos redondos que alcanzan para cubrir
/// [totalCentavos]: los atajos de "con cuánto paga". Más allá del billete
/// más grande sigue de a $50.000 hacia arriba. Total cero no ofrece nada.
List<int> atajosDeEfectivo(int totalCentavos, {int cuantos = 2}) {
  if (totalCentavos <= 0) return const [];
  final atajos = <int>[];
  for (final billete in _billetesCentavos) {
    if (billete >= totalCentavos) atajos.add(billete);
    if (atajos.length == cuantos) return atajos;
  }
  var siguiente = ((totalCentavos + _pasoSobreElMayorCentavos - 1) ~/ _pasoSobreElMayorCentavos) * _pasoSobreElMayorCentavos;
  // Sin repetir un billete ya ofrecido: un total de $90.000 ofrecía $100.000 dos veces (revisión 2026-10-03), porque
  // el primer múltiplo de $50.000 que lo cubre es justo el billete más grande.
  if (atajos.isNotEmpty && siguiente <= atajos.last) siguiente = atajos.last + _pasoSobreElMayorCentavos;
  while (atajos.length < cuantos) {
    atajos.add(siguiente);
    siguiente += _pasoSobreElMayorCentavos;
  }
  return atajos;
}

/// Lo que se devuelve: negativo si lo que paga no alcanza (falta plata).
int vueltoCentavos({required int pagaCentavos, required int totalCentavos}) => pagaCentavos - totalCentavos;

/// Cuando faltan exactamente $100 de vuelto se agrega un caramelo en vez de
/// dar el cambio (`REGLAS-NEGOCIO.md` §3): la app ofrece el atajo en ese caso.
bool vueltoEsCaramelo(int vueltoCentavos) => vueltoCentavos == 10000;
