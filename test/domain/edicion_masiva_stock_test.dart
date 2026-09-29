import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/edicion_masiva_stock.dart';

void main() {
  group('aplicarAjusteStock — nuevoFijo', () {
    test('todos quedan en el mismo stock nuevo, sin importar el actual', () {
      expect(
        aplicarAjusteStock(actual: 12, tipo: TipoAjusteStock.nuevoFijo, valor: 50),
        50,
      );
      expect(
        aplicarAjusteStock(actual: 0, tipo: TipoAjusteStock.nuevoFijo, valor: 50),
        50,
      );
    });
  });

  group('aplicarAjusteStock — sumar / restar', () {
    test('suma unidades al stock actual', () {
      expect(
        aplicarAjusteStock(actual: 10, tipo: TipoAjusteStock.sumar, valor: 5),
        15,
      );
    });

    test('resta unidades al stock actual', () {
      expect(
        aplicarAjusteStock(actual: 10, tipo: TipoAjusteStock.restar, valor: 5),
        5,
      );
    });

    test('restar más de lo que hay da negativo (Regla 8: informa, no bloquea)', () {
      expect(
        aplicarAjusteStock(actual: 3, tipo: TipoAjusteStock.restar, valor: 10),
        -7,
      );
    });
  });
}
