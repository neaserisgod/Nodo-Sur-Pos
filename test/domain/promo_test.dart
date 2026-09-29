import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/promo.dart';

void main() {
  group('repartirEnProporcion', () {
    test('reparte según el peso y la suma da exacto', () {
      final partes = repartirEnProporcion(200000, [140000, 90000]); // lista 1.400 y 900
      expect(partes.fold(0, (a, b) => a + b), 200000);
      expect(partes[0], greaterThan(partes[1]));
    });

    test('un resto que no entra exacto se reparte sin perder centavos', () {
      final partes = repartirEnProporcion(100, [1, 1, 1]);
      expect(partes.fold(0, (a, b) => a + b), 100);
      expect(partes, [34, 33, 33]);
    });

    test('con pesos en cero reparte parejo', () {
      expect(repartirEnProporcion(10, [0, 0]), [5, 5]);
    });

    test('una sola parte se lleva todo', () {
      expect(repartirEnProporcion(12345, [999]), [12345]);
    });
  });

  group('dividirEnUnidades', () {
    test('división exacta: una tanda', () {
      expect(dividirEnUnidades(300, 3), [(cantidad: 3, precioUnitarioCentavos: 100)]);
    });

    test('con resto: dos tandas y la suma da exacto', () {
      final r = dividirEnUnidades(1001, 3); // 333,67
      expect(r.fold(0, (a, t) => a + t.cantidad * t.precioUnitarioCentavos), 1001);
      expect(r.fold(0, (a, t) => a + t.cantidad), 3);
    });

    test('total 0 → sin precio', () {
      expect(dividirEnUnidades(0, 2), [(cantidad: 2, precioUnitarioCentavos: 0)]);
    });
  });

  group('stockDePromo', () {
    test('el artículo que menos rinde manda', () {
      expect(stockDePromo([(stock: 10, cantidadPorPromo: 1), (stock: 5, cantidadPorPromo: 2)]), 2);
    });

    test('un artículo sin stock o negativo deja la promo en 0', () {
      expect(stockDePromo([(stock: 10, cantidadPorPromo: 1), (stock: 0, cantidadPorPromo: 1)]), 0);
      expect(stockDePromo([(stock: -3, cantidadPorPromo: 1)]), 0);
    });

    test('sin artículos no hay promo', () {
      expect(stockDePromo(const []), 0);
    });
  });
}
