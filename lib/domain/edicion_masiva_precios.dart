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

  /// Al precio se le suma un % del COSTO: el markup sube esos puntos (El dueño, 2026-10-16: "el cálculo de suba se hace sobre
  /// el precio costo"; costo $6.000, precio $7.000 y 15 % → $7.900). Sin costo no se puede: el precio queda como está.
  sumarPorcentajeDelCosto,
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
/// [redondeoCentavos]: a cuánto se redondea hacia arriba (El dueño, 2026-10-16: "añadirle un redondeador, me dejó todos los
/// precios con números sin redondear"): al peso por defecto, o a $10, $50, $100.
///
/// Nunca da negativo: un ajuste que llevaría el precio por debajo de $0
/// (una resta más grande que el precio, o un % > 100 restando) lo deja en
/// $0 en vez de un precio negativo sin sentido de negocio.
int aplicarAjustePrecio({
  required int precioActualCentavos,
  required TipoAjustePrecio tipo,
  required int valor,
  int? costoCentavos,
  int redondeoCentavos = centavosPorPeso,
}) {
  switch (tipo) {
    case TipoAjustePrecio.sumarPorcentajeDelCosto:
      final costo = costoCentavos ?? 0;
      if (costo <= 0) return precioActualCentavos;
      return redondearFraccionHaciaArriba(
        _noNegativo(precioActualCentavos * 10000 + costo * valor),
        10000,
        redondeoCentavos,
      );
    case TipoAjustePrecio.nuevoFijo:
      return redondearHaciaArriba(_noNegativo(valor), redondeoCentavos);
    case TipoAjustePrecio.sumarMonto:
      return redondearHaciaArriba(
        _noNegativo(precioActualCentavos + valor),
        redondeoCentavos,
      );
    case TipoAjustePrecio.restarMonto:
      return redondearHaciaArriba(
        _noNegativo(precioActualCentavos - valor),
        redondeoCentavos,
      );
    case TipoAjustePrecio.sumarPorcentaje:
      final numerador = precioActualCentavos * (10000 + valor);
      return redondearFraccionHaciaArriba(
        _noNegativo(numerador),
        10000,
        redondeoCentavos,
      );
    case TipoAjustePrecio.restarPorcentaje:
      final numerador = precioActualCentavos * (10000 - valor);
      return redondearFraccionHaciaArriba(
        _noNegativo(numerador),
        10000,
        redondeoCentavos,
      );
  }
}

int _noNegativo(int valor) => valor < 0 ? 0 : valor;

/// Cuál de los dos montos calculados de un producto toca la edición masiva
/// — precio de venta o costo. Los dos usan la misma aritmética de acá
/// arriba (Regla 3: una sola fórmula), solo cambia el par de columnas que
/// se lee/escribe (`ajustarMontoEnLote` en `data/repositorio_productos.dart`).
enum CampoMonto { precio, costo }
