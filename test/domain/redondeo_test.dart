import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/redondeo.dart';

void main() {
  const pasoDefault = 10000; // $100, paso por defecto (Regla 2)

  group('redondeoDeVenta — Regla 2', () {
    test('efectivo: 54 pesos → 100 pesos, ejemplo textual de la regla', () {
      final r = redondeoDeVenta(
        totalCentavos: 5400,
        composicionPago: ComposicionPago.efectivo,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 10000);
      expect(r.montoRedondeoCentavos, 4600);
    });

    test('efectivo: 1.204 pesos → 1.300 pesos, ejemplo textual de la regla', () {
      final r = redondeoDeVenta(
        totalCentavos: 120400,
        composicionPago: ComposicionPago.efectivo,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 130000);
      expect(r.montoRedondeoCentavos, 9600);
    });

    test('virtual: no redondea, se cobra el importe exacto', () {
      final r = redondeoDeVenta(
        totalCentavos: 5400,
        composicionPago: ComposicionPago.virtual,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 5400);
      expect(r.montoRedondeoCentavos, 0);
    });

    test('mixto redondea igual que efectivo, porque hay efectivo de por medio', () {
      final r = redondeoDeVenta(
        totalCentavos: 120400,
        composicionPago: ComposicionPago.mixto,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 130000);
      expect(r.montoRedondeoCentavos, 9600);
    });

    test('total ya exacto en el paso: no hay redondeo que mostrar', () {
      final r = redondeoDeVenta(
        totalCentavos: 100000,
        composicionPago: ComposicionPago.efectivo,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 100000);
      expect(r.montoRedondeoCentavos, 0);
    });

    test('paso configurable distinto del default', () {
      final r = redondeoDeVenta(
        totalCentavos: 5050,
        composicionPago: ComposicionPago.efectivo,
        pasoCentavos: 100, // redondea al peso
      );
      expect(r.totalCentavos, 5100);
      expect(r.montoRedondeoCentavos, 50);
    });

    test('mixto: total ya exacto en el paso → tampoco redondea de más', () {
      final r = redondeoDeVenta(
        totalCentavos: 100000,
        composicionPago: ComposicionPago.mixto,
        pasoCentavos: pasoDefault,
      );
      expect(r.totalCentavos, 100000);
      expect(r.montoRedondeoCentavos, 0);
    });

    test('mixto y efectivo dan exactamente el mismo resultado para el mismo total: '
        'lo que importa es que haya efectivo de por medio, no cuánto', () {
      for (final total in [1, 5400, 54321, 99999, 100000, 120400]) {
        final conEfectivo = redondeoDeVenta(
          totalCentavos: total,
          composicionPago: ComposicionPago.efectivo,
          pasoCentavos: pasoDefault,
        );
        final conMixto = redondeoDeVenta(
          totalCentavos: total,
          composicionPago: ComposicionPago.mixto,
          pasoCentavos: pasoDefault,
        );
        expect(conMixto.totalCentavos, conEfectivo.totalCentavos, reason: 'total con $total');
        expect(conMixto.montoRedondeoCentavos, conEfectivo.montoRedondeoCentavos, reason: 'total con $total');
      }
    });
  });
}
