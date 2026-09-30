import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/dinero.dart';

void main() {
  group('formatearARS — sin centavos (Dueño, 2026-09-16)', () {
    test('monto redondo → "\$1.500"', () {
      expect(formatearARS(150000), r'$1.500');
    });

    test('centavos sueltos redondean al peso más cercano hacia arriba en .50', () {
      expect(formatearARS(150050), r'$1.501'); // $1.500,50 → $1.501
    });

    test('centavos sueltos por debajo de .50 redondean hacia abajo', () {
      expect(formatearARS(150049), r'$1.500'); // $1.500,49 → $1.500
    });

    test('menos de un peso, .50 o más → "\$1"', () {
      expect(formatearARS(50), r'$1');
    });

    test('menos de un peso, menos de .50 → "\$0"', () {
      expect(formatearARS(49), r'$0');
    });

    test('cero → "\$0"', () {
      expect(formatearARS(0), r'$0');
    });

    test('millones agrupa varios puntos de miles → "\$2.093.000"', () {
      expect(formatearARS(209300000), r'$2.093.000');
    });

    test('negativo conserva el signo → "-\$500"', () {
      expect(formatearARS(-50000), r'-$500');
    });

    test('conSigno: false omite el "\$"', () {
      expect(formatearARS(150000, conSigno: false), '1.500');
    });
  });

  group('parsearARS', () {
    test('formato es-AR completo "1.500,50"', () {
      expect(parsearARS('1.500,50'), 150050);
    });

    test('formato con punto decimal "1500.50"', () {
      expect(parsearARS('1500.50'), 150050);
    });

    test('con símbolo "\$1.500,50"', () {
      expect(parsearARS(r'$1.500,50'), 150050);
    });

    test('entero sin decimales "1500"', () {
      expect(parsearARS('1500'), 150000);
    });

    test('varios puntos de miles encadenados "2.093.000"', () {
      expect(parsearARS('2.093.000'), 209300000);
    });

    test('espacios alrededor se ignoran', () {
      expect(parsearARS('  1500  '), 150000);
    });

    test('texto inválido lanza error', () {
      expect(() => parsearARS('abc'), throwsFormatException);
    });

    test('es inverso de formatearARS para montos ya en peso entero (formatearARS '
        'redondea centavos sueltos, ya no es inverso exacto para esos)', () {
      final centavos = 172500;
      expect(parsearARS(formatearARS(centavos).replaceAll(r'$', '')), centavos);
    });
  });

  group('redondearHaciaArriba', () {
    test('54 pesos (paso 100 pesos) → 100 pesos — ejemplo de la Regla 2', () {
      expect(redondearHaciaArriba(5400, 10000), 10000);
    });

    test('1.204 pesos (paso 100 pesos) → 1.300 pesos — ejemplo de la Regla 2', () {
      expect(redondearHaciaArriba(120400, 10000), 130000);
    });

    test('monto ya exacto no cambia', () {
      expect(redondearHaciaArriba(10000, 10000), 10000);
    });

    test('cero ya es múltiplo, no cambia', () {
      expect(redondearHaciaArriba(0, 10000), 0);
    });

    test('paso de un peso entero (100 centavos) redondea centavos sueltos', () {
      expect(redondearHaciaArriba(172550, 100), 172600);
    });

    test('paso de un peso entero: monto ya en peso exacto no cambia', () {
      expect(redondearHaciaArriba(172500, 100), 172500);
    });
  });

  group('redondearFraccionHaciaArriba', () {
    test('sin resto: numerador múltiplo exacto del paso', () {
      // 17000 / 10000 = 1.7 → en pasos de 100: 1.7*100=170 → ya es "1" paso? probamos caso exacto real:
      // 1.000.000 / 10.000 = 100 (pesos), paso 100 centavos → 100 centavos exactos
      expect(redondearFraccionHaciaArriba(1000000, 10000, 100), 100);
    });

    test('con resto: redondea hacia arriba al peso entero sin redondeo intermedio', () {
      // 1050 / 10000 = 0.105 centavos... probamos con costo*markup típico:
      // costo 1000 centavos, markup 500 bp → numerador 1000*10500=10.500.000, denominador 10000
      // resultado exacto = 1050 centavos → redondea a 1100 (paso 100)
      expect(redondearFraccionHaciaArriba(1000 * 10500, 10000, 100), 1100);
    });
  });

  group('formatearParaMercadoPago — Fase 12, Orders API', () {
    test('monto con centavos exactos', () {
      expect(formatearParaMercadoPago(174000), '1740.00');
    });

    test('monto con centavos sueltos', () {
      expect(formatearParaMercadoPago(174050), '1740.50');
    });

    test('sin agrupador de miles (a diferencia de formatearARS)', () {
      expect(formatearParaMercadoPago(123456700), '1234567.00');
    });

    test('menor a un peso: la parte entera es 0', () {
      expect(formatearParaMercadoPago(50), '0.50');
    });

    test('cero', () {
      expect(formatearParaMercadoPago(0), '0.00');
    });
  });
}
