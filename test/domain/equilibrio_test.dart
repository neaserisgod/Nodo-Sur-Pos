import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/equilibrio.dart';
import 'package:la_plazoleta/domain/reposicion.dart';

void main() {
  group('calcularGananciaBruta — margen real del período (Regla 12)', () {
    test('suma precio-costo de cada línea con costo conocido', () {
      final r = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(
          proveedorId: '1',
          costoLineaCentavos: 600,
          precioLineaCentavos: 1000,
        ),
        const LineaParaReposicion(
          proveedorId: '2',
          costoLineaCentavos: 300,
          precioLineaCentavos: 500,
        ),
      ]);
      expect(r.gananciaBrutaCentavos, 600); // 400 + 200
      expect(r.ventaConCostoCentavos, 1500);
      expect(r.vendidoSinCostoCentavos, 0);
    });

    test('a diferencia de la reposición, SÍ incluye cigarrillos: su costo-foto '
        'es lo que se le paga a Distribuidora, y esa ganancia es real aunque la lata '
        'la maneje aparte', () {
      final r = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(
          proveedorId: null,
          esCigarrillo: true,
          costoLineaCentavos: 4000,
          precioLineaCentavos: 5000,
        ),
      ]);
      expect(r.gananciaBrutaCentavos, 1000);
      expect(r.ventaConCostoCentavos, 5000);
    });

    test('línea sin costo (Varios / alta rápida pendiente) no inventa ganancia: '
        'se reporta aparte como vendido sin costo', () {
      final r = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(
          proveedorId: null,
          costoLineaCentavos: null,
          precioLineaCentavos: 2000,
        ),
      ]);
      expect(r.gananciaBrutaCentavos, 0);
      expect(r.ventaConCostoCentavos, 0);
      expect(r.vendidoSinCostoCentavos, 2000);
    });

    test('el margen ponderado se mueve según el mix vendido, no es un número fijo', () {
      final rubroAltoMargen = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(
          proveedorId: '1',
          costoLineaCentavos: 650,
          precioLineaCentavos: 1000,
        ), // 35%
      ]);
      final rubroBajoMargen = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(
          proveedorId: null,
          esCigarrillo: true,
          costoLineaCentavos: 800,
          precioLineaCentavos: 1000,
        ), // 20%
      ]);
      expect(rubroAltoMargen.margenPonderado, closeTo(0.35, 0.0001));
      expect(rubroBajoMargen.margenPonderado, closeTo(0.20, 0.0001));
      expect(rubroAltoMargen.margenPonderado, isNot(rubroBajoMargen.margenPonderado));
    });

    test('sin nada vendido con costo conocido, el margen ponderado es null (no 0 falso)', () {
      final r = calcularGananciaBruta(lineas: [
        const LineaParaReposicion(proveedorId: null, costoLineaCentavos: null, precioLineaCentavos: 2000),
      ]);
      expect(r.margenPonderado, isNull);
    });
  });

  group('ventaDiariaDeEquilibrio — con el margen real, no un % fijo asumido', () {
    test('fijos mensuales / margen real / días del mes', () {
      // 2.093.000 / 0.30 / 30 ≈ 232.556 (documento dice ~231.900 con 30% redondo)
      final r = ventaDiariaDeEquilibrio(
        fijosMensualesCentavos: 209300000,
        margenPonderado: 0.30,
        diasDelMes: 30,
      );
      expect(r, 23255556);
    });

    test('con un margen más bajo, hace falta vender más por día para el mismo fijo', () {
      final conMargenAlto = ventaDiariaDeEquilibrio(
        fijosMensualesCentavos: 300000,
        margenPonderado: 0.30,
      );
      final conMargenBajo = ventaDiariaDeEquilibrio(
        fijosMensualesCentavos: 300000,
        margenPonderado: 0.20,
      );
      expect(conMargenBajo!, greaterThan(conMargenAlto!));
    });

    test('margen cero o negativo: ningún volumen alcanza, no se puede calcular', () {
      expect(
        ventaDiariaDeEquilibrio(fijosMensualesCentavos: 100000, margenPonderado: 0),
        isNull,
      );
      expect(
        ventaDiariaDeEquilibrio(fijosMensualesCentavos: 100000, margenPonderado: -0.1),
        isNull,
      );
    });
  });
  group('calcularEquilibrio — Regla 12', () {
    test('cubierto: ganancia bruta > gastos fijos', () {
      final r = calcularEquilibrio(
        gastosFijosCentavos: 1000000,
        gananciaBrutaCentavos: 1500000,
      );
      expect(r.cubierto, true);
      expect(r.faltanteCentavos, 0);
      expect(r.pctAvance, 100);
      expect(r.gananciaNetaCentavos, 500000);
    });

    test('no cubierto: ganancia bruta < gastos fijos', () {
      final r = calcularEquilibrio(
        gastosFijosCentavos: 2000000,
        gananciaBrutaCentavos: 800000,
      );
      expect(r.cubierto, false);
      expect(r.faltanteCentavos, 1200000);
      expect(r.pctAvance, 40);
      expect(r.gananciaNetaCentavos, -1200000);
    });

    test('exactamente cubierto: ganancia bruta = gastos fijos', () {
      final r = calcularEquilibrio(
        gastosFijosCentavos: 500000,
        gananciaBrutaCentavos: 500000,
      );
      expect(r.cubierto, true);
      expect(r.faltanteCentavos, 0);
      expect(r.pctAvance, 100);
      expect(r.gananciaNetaCentavos, 0);
    });

    test('sin gastos fijos configurados → siempre cubierto con 100%', () {
      final r = calcularEquilibrio(
        gastosFijosCentavos: 0,
        gananciaBrutaCentavos: 100000,
      );
      expect(r.cubierto, true);
      expect(r.pctAvance, 100);
      expect(r.faltanteCentavos, 0);
    });

    test('sin ventas en el mes: 0% de avance y falta todo', () {
      final r = calcularEquilibrio(
        gastosFijosCentavos: 1000000,
        gananciaBrutaCentavos: 0,
      );
      expect(r.pctAvance, 0);
      expect(r.faltanteCentavos, 1000000);
      expect(r.gananciaNetaCentavos, -1000000);
    });
  });

  group('reservaDiariaFijosCentavos — Regla 12', () {
    test('ejemplo del documento: ~2.093.000 mensuales → ~70.000 diarios', () {
      final r = reservaDiariaFijosCentavos(fijosMensualesCentavos: 209300000);
      // 209300000 / 30 = 6976666.67 → redondea a 6976667 (≈ $69.766,67)
      expect(r, 6976667);
    });

    test('divide por 30 días por defecto', () {
      expect(reservaDiariaFijosCentavos(fijosMensualesCentavos: 3000000), 100000);
    });

    test('acepta una cantidad de días distinta (ej. mes de 31)', () {
      expect(
        reservaDiariaFijosCentavos(fijosMensualesCentavos: 3100000, diasDelMes: 31),
        100000,
      );
    });

    test('sin fijos cargados → reserva 0, no un error', () {
      expect(reservaDiariaFijosCentavos(fijosMensualesCentavos: 0), 0);
    });
  });

  group('estadoDelFijo (mock v4: "Pagado", "Pendiente", "Falta cargar")', () {
    test('sin monto cargado del mes: falta cargar, aunque haya pagos', () {
      expect(estadoDelFijo(montoCentavos: null, pagadoCentavos: 0), EstadoFijo.faltaCargar);
      expect(estadoDelFijo(montoCentavos: null, pagadoCentavos: 500), EstadoFijo.faltaCargar);
    });
    test('pagado completo o de más: pagado', () {
      expect(estadoDelFijo(montoCentavos: 1000, pagadoCentavos: 1000), EstadoFijo.pagado);
      expect(estadoDelFijo(montoCentavos: 1000, pagadoCentavos: 1200), EstadoFijo.pagado);
    });
    test('pago parcial o ninguno: pendiente', () {
      expect(estadoDelFijo(montoCentavos: 1000, pagadoCentavos: 400), EstadoFijo.pendiente);
      expect(estadoDelFijo(montoCentavos: 1000, pagadoCentavos: 0), EstadoFijo.pendiente);
    });
  });
}
