import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/faltantes_cierre.dart';

void main() {
  group('faltantesPorExplicar', () {
    test('la comisión diaria de Mercado Pago no se pregunta (caso real: −\$5.292)', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: 0, diferenciaMpCentavos: -529200, diferenciaLataCentavos: 0);
      expect(r, isEmpty);
    });

    test('un faltante grande de Mercado Pago se pregunta, en positivo (caso real del 3/10: −\$110.898)', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: 0, diferenciaMpCentavos: -11089800, diferenciaLataCentavos: 0);
      expect(r, {CajaDelCierre.mercadoPago: 11089800});
    });

    test('justo en el umbral se pregunta', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: -umbralFaltanteCentavos, diferenciaMpCentavos: null, diferenciaLataCentavos: null);
      expect(r, {CajaDelCierre.efectivo: umbralFaltanteCentavos});
    });

    test('un sobrante no se pregunta: no hay salida que explicar', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: 5000000, diferenciaMpCentavos: 5000000, diferenciaLataCentavos: 5000000);
      expect(r, isEmpty);
    });

    test('una caja sin contar (null) no se pregunta', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: 0, diferenciaMpCentavos: null, diferenciaLataCentavos: null);
      expect(r, isEmpty);
    });

    test('pregunta por cada caja que falta, por separado', () {
      final r = faltantesPorExplicar(diferenciaEfectivoCentavos: -1000000, diferenciaMpCentavos: -2000000, diferenciaLataCentavos: -3000000);
      expect(r, {CajaDelCierre.efectivo: 1000000, CajaDelCierre.mercadoPago: 2000000, CajaDelCierre.lata: 3000000});
    });
  });
}
