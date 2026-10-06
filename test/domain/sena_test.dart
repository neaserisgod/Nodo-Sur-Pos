// Seña de encargues (rediseño v4, etapa 8.4). Decisiones del dueño (2026-10-06):
//  - la seña entra en la caja con la que se pagó (cajón si fue efectivo, Mercado Pago si no);
//  - es un ingreso de caja, NO una venta;
//  - cuando el encargue se paga completo pasa a ser venta DEL DÍA en que se completó, por el total (a precios de ese día),
//    y lo ya cobrado de seña cuenta como pago de esa venta sin volver a tocar la caja;
//  - si el encargue se cancela, la seña se devuelve por la misma caja.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/sena.dart';

void main() {
  group('aplicarSena (al entregar)', () {
    test('sin seña: se cobra todo', () {
      final a = aplicarSena(totalCentavos: 500000, senaCentavos: 0);
      expect(a.aplicadaCentavos, 0);
      expect(a.aCobrarCentavos, 500000);
      expect(a.aDevolverCentavos, 0);
    });

    test('con seña menor al total: se descuenta y se cobra el resto', () {
      final a = aplicarSena(totalCentavos: 500000, senaCentavos: 200000);
      expect(a.aplicadaCentavos, 200000);
      expect(a.aCobrarCentavos, 300000);
      expect(a.aDevolverCentavos, 0);
    });

    test('seña igual al total: no se cobra nada más', () {
      final a = aplicarSena(totalCentavos: 500000, senaCentavos: 500000);
      expect(a.aplicadaCentavos, 500000);
      expect(a.aCobrarCentavos, 0);
      expect(a.aDevolverCentavos, 0);
    });

    test('seña mayor al total (bajó un precio): se aplica el total y se devuelve la diferencia', () {
      final a = aplicarSena(totalCentavos: 400000, senaCentavos: 500000);
      expect(a.aplicadaCentavos, 400000);
      expect(a.aCobrarCentavos, 0);
      expect(a.aDevolverCentavos, 100000);
    });

    test('una seña negativa es un error', () {
      expect(() => aplicarSena(totalCentavos: 100, senaCentavos: -1), throwsArgumentError);
    });
  });

  group('validarSenaNueva (al encargar)', () {
    test('cero es "sin seña" y es válido', () => expect(validarSenaNueva(senaCentavos: 0, estimadoCentavos: 500000), isNull));

    test('una seña razonable es válida', () => expect(validarSenaNueva(senaCentavos: 200000, estimadoCentavos: 500000), isNull));

    test('negativa se rechaza', () => expect(validarSenaNueva(senaCentavos: -1, estimadoCentavos: 500000), isNotNull));

    test('más que lo estimado se rechaza: sería devolver plata por adelantado', () {
      expect(validarSenaNueva(senaCentavos: 600000, estimadoCentavos: 500000), isNotNull);
    });
  });

  group('lo que cuenta cada caja', () {
    test('la seña al cobrarla es un ingreso en la caja con la que se pagó', () {
      expect(cajaDeLaSena(esEfectivo: true), CajaDeSena.cajon);
      expect(cajaDeLaSena(esEfectivo: false), CajaDeSena.mercadoPago);
    });
  });
}
