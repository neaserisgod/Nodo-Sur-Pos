import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/tecleo.dart';
import 'package:la_plazoleta/domain/turnos.dart' show minutosDeHora;

void main() {
  group('horaTecleada (el teclado numérico no trae ":")', () {
    test('pone los dos puntos sola a medida que se teclea', () {
      expect(horaTecleada(''), '');
      expect(horaTecleada('2'), '2');
      expect(horaTecleada('20'), '20');
      expect(horaTecleada('200'), '2:00');
      expect(horaTecleada('2000'), '20:00');
      expect(horaTecleada('0930'), '09:30');
    });

    test('tolera los ":" o "." tecleados y corta en 4 dígitos', () {
      expect(horaTecleada('20:00'), '20:00');
      expect(horaTecleada('9.30'), '9:30');
      expect(horaTecleada('20:005'), '20:00');
    });

    test('lo que deja es una hora que se entiende', () {
      expect(minutosDeHora(horaTecleada('930')), 570);
      expect(minutosDeHora(horaTecleada('2000')), 1200);
    });
  });

  group('fechaTecleada (el teclado numérico no trae "/")', () {
    test('pone las barras sola a medida que se teclea', () {
      expect(fechaTecleada(''), '');
      expect(fechaTecleada('1'), '1');
      expect(fechaTecleada('10'), '10');
      expect(fechaTecleada('101'), '10/1');
      expect(fechaTecleada('1010'), '10/10');
      expect(fechaTecleada('10102'), '10/10/2');
      expect(fechaTecleada('10102026'), '10/10/2026');
    });

    test('tolera las "/" tecleadas y corta en 8 dígitos', () {
      expect(fechaTecleada('10/10/2026'), '10/10/2026');
      expect(fechaTecleada('10/10/20261'), '10/10/2026');
    });
  });
}
