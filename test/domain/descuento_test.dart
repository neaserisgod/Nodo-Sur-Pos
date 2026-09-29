import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/descuento.dart';

void main() {
  group('calcularDescuento', () {
    test('monto simple: resta el monto tal cual', () {
      final descuento = calcularDescuento(
        baseCentavos: 1000000, // $10.000
        tipo: TipoDescuento.monto,
        valor: 50000, // $500
      );
      expect(descuento, 50000);
    });

    test(
      'porcentaje simple: basis points, mismo lenguaje que markupDefaultBp',
      () {
        final descuento = calcularDescuento(
          baseCentavos: 1000000, // $10.000
          tipo: TipoDescuento.porcentaje,
          valor: 1000, // 10.00%
        );
        expect(descuento, 100000); // $1.000
      },
    );

    test('caso real: Jam Rock, 15% sobre el importe total (Regla 17)', () {
      final descuento = calcularDescuento(
        baseCentavos: 850000, // $8.500 de paleta y queso
        tipo: TipoDescuento.porcentaje,
        valor: 1500, // 15.00%
      );
      expect(descuento, 127500); // $1.275
    });

    test('un valor negativo nunca resta de más: se recorta en 0', () {
      final descuento = calcularDescuento(
        baseCentavos: 1000000,
        tipo: TipoDescuento.monto,
        valor: -50000,
      );
      expect(descuento, 0);
    });

    test(
      'un monto mayor a la base se recorta en la base — nunca deja un total negativo',
      () {
        final descuento = calcularDescuento(
          baseCentavos: 1000000,
          tipo: TipoDescuento.monto,
          valor: 5000000,
        );
        expect(descuento, 1000000);
      },
    );

    test('un porcentaje mayor a 100% se recorta en la base, mismo motivo', () {
      final descuento = calcularDescuento(
        baseCentavos: 1000000,
        tipo: TipoDescuento.porcentaje,
        valor: 15000, // 150%
      );
      expect(descuento, 1000000);
    });

    test(
      'base en 0 (carrito vacío): el descuento siempre es 0, sin dividir por nada raro',
      () {
        expect(
          calcularDescuento(
            baseCentavos: 0,
            tipo: TipoDescuento.monto,
            valor: 50000,
          ),
          0,
        );
        expect(
          calcularDescuento(
            baseCentavos: 0,
            tipo: TipoDescuento.porcentaje,
            valor: 1000,
          ),
          0,
        );
      },
    );
  });
}
