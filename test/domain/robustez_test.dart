// Bordes de las cuentas ante datos raros que puede tipear el usuario: lo que
// antes tiraba un error no capturado, daba un monto basura o un total
// negativo. Cada caso es un dato que el negocio puede producir de verdad.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/caja.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/dinero.dart';
import 'package:la_plazoleta/domain/equilibrio.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/pesables.dart';
import 'package:la_plazoleta/domain/promo.dart';
import 'package:la_plazoleta/domain/redondeo.dart';
import 'package:la_plazoleta/domain/reposicion.dart';

void main() {
  group('parsearARS — estricto', () {
    test('notación científica, NaN e Infinity no son montos', () {
      for (final texto in ['1e3', '1E5', 'NaN', 'Infinity', '-Infinity', '0x10']) {
        expect(() => parsearARS(texto), throwsFormatException, reason: texto);
      }
    });

    test('basura mezclada con números se rechaza', () {
      for (final texto in ['12abc', '1,2,3', '1.2.3', '1,5,0', '--5', '', ' ', r'$', '.', ',']) {
        expect(() => parsearARS(texto), throwsFormatException, reason: '"$texto"');
      }
    });

    test('un monto absurdo se rechaza en vez de desbordar las cuentas', () {
      expect(() => parsearARS('99999999999999999999'), throwsFormatException);
      expect(() => parsearARS('200000000000'), throwsFormatException); // > \$100.000.000.000
    });

    test('el tope exacto se acepta', () {
      expect(parsearARS('100000000000'), maximoMontoCentavos);
    });

    test('decimales: coma o punto, medio centavo hacia arriba', () {
      expect(parsearARS('1,5'), 150);
      expect(parsearARS('0.29'), 29); // 0.29 * 100 en double daba 28.999…
      expect(parsearARS('10,005'), 1001);
      expect(parsearARS('10,004'), 1000);
      expect(parsearARS(',5'), 50);
    });

    test('el punto es miles solo con grupos de exactamente 3 dígitos', () {
      expect(parsearARS('1.500'), 150000);
      expect(parsearARS('12.345.678'), 1234567800);
      expect(parsearARS('1.5'), 150);
      expect(parsearARS('0.500'), 50); // medio peso, no \$500
      expect(parsearARS('1.500,25'), 150025);
      expect(() => parsearARS('1.50.0,5'), throwsFormatException);
    });

    test('negativos se parsean con su signo', () {
      expect(parsearARS('-200'), -20000);
      expect(parsearARS(r'-$1.500,50'), -150050);
    });
  });

  group('redondearFraccionHaciaArriba', () {
    test('es un techo verdadero también con numerador negativo', () {
      expect(redondearFraccionHaciaArriba(-150, 1, 100), -100);
      expect(redondearFraccionHaciaArriba(-100, 1, 100), -100);
      expect(redondearFraccionHaciaArriba(-50, 1, 100), 0);
    });

    test('un paso o denominador ≤ 0 lanza ArgumentError, no división por cero', () {
      expect(() => redondearHaciaArriba(100, 0), throwsArgumentError);
      expect(() => redondearHaciaArriba(100, -100), throwsArgumentError);
      expect(() => redondearFraccionHaciaArriba(100, 0, 100), throwsArgumentError);
    });
  });

  group('redondeoDeVenta con una configuración rota', () {
    test('paso 0 no traba el cobro: se cobra el total exacto', () {
      final r = redondeoDeVenta(totalCentavos: 123456, composicionPago: ComposicionPago.efectivo, pasoCentavos: 0);
      expect(r.totalCentavos, 123456);
      expect(r.montoRedondeoCentavos, 0);
    });
  });

  group('subtotalPesable — cuenta entera', () {
    test('200 g a \$1.000/kg = \$200', () {
      expect(subtotalPesable(montoPorKiloCentavos: 100000, gramos: 200), 20000);
    });

    test('medio centavo sube, menos de medio baja', () {
      expect(subtotalPesable(montoPorKiloCentavos: 5, gramos: 100), 1); // 0,5 centavos → 1
      expect(subtotalPesable(montoPorKiloCentavos: 5, gramos: 99), 0); // 0,495 → 0
    });

    test('0 gramos da 0', () {
      expect(subtotalPesable(montoPorKiloCentavos: 123456, gramos: 0), 0);
    });
  });

  group('calcularDescuento', () {
    test('sobre una base 0 o negativa no descuenta (y no lanza)', () {
      expect(calcularDescuento(baseCentavos: 0, tipo: TipoDescuento.monto, valor: 500), 0);
      expect(calcularDescuento(baseCentavos: -100, tipo: TipoDescuento.porcentaje, valor: 1000), 0);
    });

    test('porcentaje mayor a 100% se limita al total', () {
      expect(calcularDescuento(baseCentavos: 50000, tipo: TipoDescuento.porcentaje, valor: 25000), 50000);
    });

    test('monto negativo o 0 no descuenta', () {
      expect(calcularDescuento(baseCentavos: 50000, tipo: TipoDescuento.monto, valor: -500), 0);
    });

    test('el porcentaje trunca hacia abajo: nunca se regala un centavo de más', () {
      // 15% de 100,01 = 15,0015 → 15,00
      expect(calcularDescuento(baseCentavos: 10001, tipo: TipoDescuento.porcentaje, valor: 1500), 1500);
    });
  });

  group('caja', () {
    test('separarCigarrillos con efectivo contado negativo no separa nada', () {
      final r = separarCigarrillos(
        efectivoContadoCentavos: -5000,
        precioListaCigarrillosVendidosHoyCentavos: 100000,
        pendienteDeCierresAnterioresCentavos: 0,
      );
      expect(r.separadoCentavos, 0);
      expect(r.pendienteCentavos, 100000);
      expect(r.quedaEnCajonCentavos, -5000);
    });

    test('lo separado + lo pendiente siempre suma lo que había que separar', () {
      for (final contado in [0, 1, 99999, 100000, 250000]) {
        final r = separarCigarrillos(
          efectivoContadoCentavos: contado,
          precioListaCigarrillosVendidosHoyCentavos: 100000,
          pendienteDeCierresAnterioresCentavos: 30000,
        );
        expect(r.separadoCentavos + r.pendienteCentavos, 130000, reason: 'contado $contado');
        expect(r.separadoCentavos <= contado, isTrue);
      }
    });
  });

  group('prorratearGananciaPorMedio', () {
    test('una venta sin cobro registrado no divide por cero', () {
      final r = prorratearGananciaPorMedio(gananciaCentavos: 5000, efectivoDeLaVentaCentavos: 0, virtualDeLaVentaCentavos: 0);
      expect(r.efectivoCentavos + r.virtualCentavos, 5000);
    });

    test('la suma siempre es exacta', () {
      final r = prorratearGananciaPorMedio(gananciaCentavos: 1001, efectivoDeLaVentaCentavos: 333, virtualDeLaVentaCentavos: 667);
      expect(r.efectivoCentavos + r.virtualCentavos, 1001);
    });
  });

  group('equilibrio con días del mes inválidos', () {
    test('0 días no tira error', () {
      expect(ventaDiariaDeEquilibrio(fijosMensualesCentavos: 100000, margenPonderado: 0.3, diasDelMes: 0), isNull);
      expect(reservaDiariaFijosCentavos(fijosMensualesCentavos: 100000, diasDelMes: 0), 0);
    });
  });

  group('stockDePromo', () {
    test('un artículo con cantidad 0 por promo no divide por cero', () {
      expect(stockDePromo([(stock: 5, cantidadPorPromo: 0)]), 0);
    });
  });
}
