// Edición masiva de precios (El dueño, 2026-09-16: "si quiero subir el precio
// de 3 productos iguales de distinta variante, hacerlo a la vez"). Una sola
// fórmula (Regla 3) que la UI de Proveedores aplica producto por producto —
// esto no toca la base ni el catálogo, solo calcula el precio nuevo a partir
// del actual.

import 'dinero.dart';

/// Las tres formas de ajuste que puede pedir un cambio masivo. Los dos pares
/// sumar/restar quedan separados (en vez de un solo "ajustar" con signo) para
/// que la UI pueda ofrecerlos como dos botones sin inventar una convención de
/// signo que alguien va a leer mal ("-10%" vs "restar 10%").
enum TipoAjustePrecio {
  /// Todos los productos elegidos quedan al mismo precio nuevo — para
  /// variantes que tienen que terminar igualadas.
  nuevoFijo,
  sumarMonto,
  restarMonto,
  sumarPorcentaje,
  restarPorcentaje,
}

/// Calcula el precio nuevo de UN producto dado su precio actual y el ajuste
/// elegido. [valor] es centavos para `nuevoFijo`/`sumarMonto`/`restarMonto`,
/// y basis points (10000 = 100%) para `sumarPorcentaje`/`restarPorcentaje` —
/// mismo lenguaje que `markupBp`/`descuentoBp` en el resto de la app.
///
/// Redondea siempre hacia arriba al peso entero (Regla 1 de convenciones,
/// `centavosPorPeso`), en una sola operación exacta para el caso porcentual
/// (`redondearFraccionHaciaArriba`) — encadenar dos redondeos alejaría el
/// resultado del valor exacto más de lo que hace uno solo (mismo motivo que
/// ya documenta `dinero.dart` para el triángulo de markup).
///
/// Nunca da negativo: un ajuste que llevaría el precio por debajo de $0
/// (una resta más grande que el precio, o un % > 100 restando) lo deja en
/// $0 en vez de un precio negativo sin sentido de negocio.
int aplicarAjustePrecio({
  required int precioActualCentavos,
  required TipoAjustePrecio tipo,
  required int valor,
}) {
  switch (tipo) {
    case TipoAjustePrecio.nuevoFijo:
      return redondearHaciaArriba(_noNegativo(valor), centavosPorPeso);
    case TipoAjustePrecio.sumarMonto:
      return redondearHaciaArriba(
        _noNegativo(precioActualCentavos + valor),
        centavosPorPeso,
      );
    case TipoAjustePrecio.restarMonto:
      return redondearHaciaArriba(
        _noNegativo(precioActualCentavos - valor),
        centavosPorPeso,
      );
    case TipoAjustePrecio.sumarPorcentaje:
      final numerador = precioActualCentavos * (10000 + valor);
      return redondearFraccionHaciaArriba(
        _noNegativo(numerador),
        10000,
        centavosPorPeso,
      );
    case TipoAjustePrecio.restarPorcentaje:
      final numerador = precioActualCentavos * (10000 - valor);
      return redondearFraccionHaciaArriba(
        _noNegativo(numerador),
        10000,
        centavosPorPeso,
      );
  }
}

int _noNegativo(int valor) => valor < 0 ? 0 : valor;

/// Cuál de los dos montos calculados de un producto toca la edición masiva
/// — precio de venta o costo. Los dos usan la misma aritmética de acá
/// arriba (Regla 3: una sola fórmula), solo cambia el par de columnas que
/// se lee/escribe (`ajustarMontoEnLote` en `data/repositorio_productos.dart`).
enum CampoMonto { precio, costo }
