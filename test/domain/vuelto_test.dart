import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/vuelto.dart';

void main() {
  group('atajosDeEfectivo — con cuánto paga', () {
    test('ofrece los dos primeros billetes que alcanzan para cubrir el total', () {
      // $11.510: el de $10.000 no alcanza, se ofrecen $20.000 y $50.000.
      expect(atajosDeEfectivo(1151000), [2000000, 5000000]);
    });

    test('un total chico arranca por el billete más chico', () {
      expect(atajosDeEfectivo(120000), [200000, 500000]);
    });

    test('un total que es justo un billete lo ofrece a él y al siguiente', () {
      // Pagar justo con un billete sigue siendo un atajo útil (vuelto cero).
      expect(atajosDeEfectivo(2000000), [2000000, 5000000]);
    });

    test('un total que supera el billete más grande ofrece el múltiplo siguiente', () {
      // $130.000: no hay billete de $100.000 que alcance, se redondea hacia arriba a $150.000 y $200.000.
      expect(atajosDeEfectivo(13000000), [15000000, 20000000]);
    });

    test('total cero no ofrece nada', () {
      expect(atajosDeEfectivo(0), isEmpty);
    });
  });

  group('vueltoCentavos', () {
    test('paga de más: devuelve la diferencia', () {
      expect(vueltoCentavos(pagaCentavos: 2000000, totalCentavos: 1151000), 849000);
    });

    test('paga justo: vuelto cero', () {
      expect(vueltoCentavos(pagaCentavos: 1151000, totalCentavos: 1151000), 0);
    });

    test('paga de menos: da negativo (falta plata), nunca se oculta', () {
      expect(vueltoCentavos(pagaCentavos: 1000000, totalCentavos: 1151000), -151000);
    });
  });

  group('vueltoEsCaramelo (REGLAS-NEGOCIO §3)', () {
    test('exactamente \$100 de vuelto', () {
      expect(vueltoEsCaramelo(10000), isTrue);
    });

    test('cualquier otro vuelto no', () {
      expect(vueltoEsCaramelo(9900), isFalse);
      expect(vueltoEsCaramelo(10100), isFalse);
      expect(vueltoEsCaramelo(0), isFalse);
      expect(vueltoEsCaramelo(-10000), isFalse);
    });
  });
}
