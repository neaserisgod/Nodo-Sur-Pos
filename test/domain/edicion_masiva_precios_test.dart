import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/edicion_masiva_precios.dart';

void main() {
  group('aplicarAjustePrecio — nuevoFijo', () {
    test('todos quedan al mismo precio nuevo, sin importar el actual', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 112000,
          tipo: TipoAjustePrecio.nuevoFijo,
          valor: 150000,
        ),
        150000,
      );
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 500,
          tipo: TipoAjustePrecio.nuevoFijo,
          valor: 150000,
        ),
        150000,
      );
    });

    test('redondea hacia arriba al peso entero si el valor no es exacto', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 0,
          tipo: TipoAjustePrecio.nuevoFijo,
          valor: 150001, // $1.500,01
        ),
        150100, // $1.501,00
      );
    });

    test(r'un valor negativo se deja en $0, no en negativo', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 100000,
          tipo: TipoAjustePrecio.nuevoFijo,
          valor: -500,
        ),
        0,
      );
    });
  });

  group('aplicarAjustePrecio — sumarMonto / restarMonto', () {
    test('suma un monto fijo en centavos', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 112000, // $1.120,00
          tipo: TipoAjustePrecio.sumarMonto,
          valor: 20000, // $200,00
        ),
        132000, // $1.320,00
      );
    });

    test('resta un monto fijo en centavos', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 112000,
          tipo: TipoAjustePrecio.restarMonto,
          valor: 20000,
        ),
        92000,
      );
    });

    test(r'restar más de lo que vale el producto lo deja en $0', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 5000,
          tipo: TipoAjustePrecio.restarMonto,
          valor: 20000,
        ),
        0,
      );
    });

    test('el resultado se redondea hacia arriba al peso entero', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 111050, // $1.110,50
          tipo: TipoAjustePrecio.sumarMonto,
          valor: 1, // un centavo
        ),
        111100, // $1.111,00, no $1.110,51
      );
    });
  });

  group('aplicarAjustePrecio — sumarPorcentaje / restarPorcentaje', () {
    test('sube el precio un 10%', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 100000, // $1.000,00
          tipo: TipoAjustePrecio.sumarPorcentaje,
          valor: 1000, // 10% en basis points
        ),
        110000, // $1.100,00
      );
    });

    test('baja el precio un 15%', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 200000, // $2.000,00
          tipo: TipoAjustePrecio.restarPorcentaje,
          valor: 1500, // 15%
        ),
        170000, // $1.700,00
      );
    });

    test('un % que no da un peso entero redondea hacia arriba, una sola vez '
        '(no al centavo y después al peso)', () {
      // $1.199,00 + 10% = $1.318,90 → redondeado al peso: $1.319,00.
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 119900,
          tipo: TipoAjustePrecio.sumarPorcentaje,
          valor: 1000,
        ),
        131900,
      );
    });

    test(r'restar más del 100% lo deja en $0', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 100000,
          tipo: TipoAjustePrecio.restarPorcentaje,
          valor: 15000, // 150%
        ),
        0,
      );
    });

    test('sumar 0% deja el mismo precio (ya redondeado)', () {
      expect(
        aplicarAjustePrecio(
          precioActualCentavos: 112000,
          tipo: TipoAjustePrecio.sumarPorcentaje,
          valor: 0,
        ),
        112000,
      );
    });
  });
}
