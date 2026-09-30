import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';

void main() {
  group('clasificarComposicion — la composición real sale de los montos, no del botón', () {
    test('efectivo en 0: es virtual puro (Dueño: no redondea, ítem 4)', () {
      expect(
        clasificarComposicion(montoEfectivoCentavos: 0, totalCentavos: 480000),
        ComposicionPago.virtual,
      );
    });

    test('efectivo negativo (no debería pasar, pero por las dudas): también virtual puro', () {
      expect(
        clasificarComposicion(montoEfectivoCentavos: -100, totalCentavos: 480000),
        ComposicionPago.virtual,
      );
    });

    test('efectivo igual al total: es efectivo puro (sin recargo de cigarrillos, ítem 4)', () {
      expect(
        clasificarComposicion(montoEfectivoCentavos: 480000, totalCentavos: 480000),
        ComposicionPago.efectivo,
      );
    });

    test('efectivo mayor al total (no debería pasar, pero por las dudas): también efectivo puro', () {
      expect(
        clasificarComposicion(montoEfectivoCentavos: 500000, totalCentavos: 480000),
        ComposicionPago.efectivo,
      );
    });

    test('efectivo entre 0 y el total: mixto de verdad', () {
      expect(
        clasificarComposicion(montoEfectivoCentavos: 200000, totalCentavos: 480000),
        ComposicionPago.mixto,
      );
    });
  });

  group('composicionPagoDesdeTexto — vocabulario compartido servidor/local', () {
    test('"efectivo" da ComposicionPago.efectivo', () {
      expect(composicionPagoDesdeTexto('efectivo'), ComposicionPago.efectivo);
    });

    test('"virtual" da ComposicionPago.virtual', () {
      expect(composicionPagoDesdeTexto('virtual'), ComposicionPago.virtual);
    });

    test('"mixto" da ComposicionPago.mixto', () {
      expect(composicionPagoDesdeTexto('mixto'), ComposicionPago.mixto);
    });

    test('cualquier otro texto tira FormatException', () {
      expect(
        () => composicionPagoDesdeTexto('tarjeta'),
        throwsFormatException,
      );
    });
  });
}
