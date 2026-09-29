import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/pesables.dart';

void main() {
  group('subtotalPesable — punto único de cálculo (Regla 7)', () {
    test('200 gramos de queso a \$1.200/kg → subtotal 240 (redondeo normal, no al peso)', () {
      expect(subtotalPesable(montoPorKiloCentavos: 120000, gramos: 200), 24000);
    });

    test('350 gramos a \$1.199/kg → redondeo aritmético al centavo, sin ceil al peso', () {
      // 119900 * 350 / 1000 = 41965 exacto, sin decimales — caso limpio
      expect(subtotalPesable(montoPorKiloCentavos: 119900, gramos: 350), 41965);
    });

    test('gramos que dejan resto de centavo redondean al centavo más cercano', () {
      // 100 * 333 / 1000 = 33.3 → redondeo normal a 33, NO hacia arriba al peso
      expect(subtotalPesable(montoPorKiloCentavos: 100, gramos: 333), 33);
    });

    test('0 gramos → subtotal 0', () {
      expect(subtotalPesable(montoPorKiloCentavos: 120000, gramos: 0), 0);
    });

    test('1000 gramos (1kg) → subtotal = precio por kilo exacto', () {
      expect(subtotalPesable(montoPorKiloCentavos: 250000, gramos: 1000), 250000);
    });

    test('sin precio/costo por kilo cargado: es un error, no un cero silencioso (Regla 7)', () {
      expect(
        () => subtotalPesable(montoPorKiloCentavos: null, gramos: 200),
        throwsStateError,
      );
    });

    test('137 gramos a un precio que no divide redondo: redondea al centavo, no se trunca', () {
      // 235900 * 137 / 1000 = 32318.3 exacto → redondea a 32318, no 32319 y
      // no se trunca a 32318 "porque sí": es el redondeo aritmético normal,
      // no un descarte de decimales.
      expect(subtotalPesable(montoPorKiloCentavos: 235900, gramos: 137), 32318);
    });

    test('fracción exacta de 0,5 centavos redondea hacia arriba (mitad para arriba)', () {
      // 100 * 5005 / 1000 = 500.5 exacto → el redondeo aritmético normal
      // (mitad hacia arriba) da 501, no 500. Es el caso donde más fácil se
      // cuela un error si alguien trunca en vez de redondear.
      expect(subtotalPesable(montoPorKiloCentavos: 100, gramos: 5005), 501);
    });

    test('costo-foto de una línea pesable usa el mismo helper que el precio (Regla 4 + Regla 7)', () {
      final precioLinea = subtotalPesable(montoPorKiloCentavos: 300000, gramos: 400);
      final costoLinea = subtotalPesable(montoPorKiloCentavos: 180000, gramos: 400);
      expect(precioLinea, 120000);
      expect(costoLinea, 72000);
    });
  });

  group('stockGramosPosterior', () {
    test('descuenta gramos vendidos del stock', () {
      expect(stockGramosPosterior(stockGramosAnterior: 5000, gramosVendidos: 350), 4650);
    });

    test('puede quedar negativo — el stock informa, no bloquea (Regla 8)', () {
      expect(stockGramosPosterior(stockGramosAnterior: 200, gramosVendidos: 350), -150);
    });
  });
}
