// Dónde sale el QR al cobrar (`domain/cobro_qr.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/cobro_qr.dart';

void main() {
  test('sin terminal elegida, el QR va siempre en la pantalla', () {
    for (final d in DondeQr.values) {
      expect(qrEnPantalla(d, hayTerminal: false), isTrue, reason: d.name);
    }
  });

  test('con terminal: automático y terminal van a la Point, pantalla a la pantalla, preguntar pregunta', () {
    expect(qrEnPantalla(DondeQr.automatico, hayTerminal: true), isFalse);
    expect(qrEnPantalla(DondeQr.terminal, hayTerminal: true), isFalse);
    expect(qrEnPantalla(DondeQr.pantalla, hayTerminal: true), isTrue);
    expect(qrEnPantalla(DondeQr.preguntar, hayTerminal: true), isNull);
  });

  test('tarjeta solo con terminal; sin saber, se deja como estaba', () {
    expect(ofrecerTarjeta(hayTerminal: true), isTrue);
    expect(ofrecerTarjeta(hayTerminal: false), isFalse);
    expect(ofrecerTarjeta(hayTerminal: null), isTrue);
  });

  test('la clave guardada vuelve a su opción; una rota o vieja es automático', () {
    for (final d in DondeQr.values) {
      expect(DondeQr.desdeClave(d.clave), d);
    }
    expect(DondeQr.desdeClave(null), DondeQr.automatico);
    expect(DondeQr.desdeClave('cualquiera'), DondeQr.automatico);
  });
}
