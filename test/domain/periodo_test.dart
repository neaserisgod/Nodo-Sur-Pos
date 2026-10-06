import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/periodo.dart';

void main() {
  group('inicioDePeriodo', () {
    // Miércoles 2026-09-02 14:30 — cualquier hora del día, para confirmar
    // que "hoy" corta a la medianoche, no a la hora actual.
    final miercoles = DateTime(2026, 9, 2, 14, 30);

    test('hoy: la medianoche del día actual, sin importar la hora', () {
      expect(inicioDePeriodo(PeriodoResumen.hoy, miercoles), DateTime(2026, 9, 2));
    });

    test('semana: el lunes de la semana en curso', () {
      expect(inicioDePeriodo(PeriodoResumen.semana, miercoles), DateTime(2026, 8, 31));
    });

    test('semana con "ahora" ya siendo lunes: el mismo día', () {
      final lunes = DateTime(2026, 9, 7, 9, 0);
      expect(inicioDePeriodo(PeriodoResumen.semana, lunes), DateTime(2026, 9, 7));
    });

    test('semana con "ahora" siendo domingo: el lunes anterior, no el mismo día', () {
      final domingo = DateTime(2026, 9, 6, 23, 0);
      expect(inicioDePeriodo(PeriodoResumen.semana, domingo), DateTime(2026, 8, 31));
    });

    test('mes: el primer día del mes en curso', () {
      expect(inicioDePeriodo(PeriodoResumen.mes, miercoles), DateTime(2026, 9, 1));
    });

    test('desde el último pago: la fecha de ese pago, tal cual', () {
      final ultimoPago = DateTime(2026, 8, 15, 10, 0);
      expect(inicioDePeriodo(PeriodoResumen.desdeUltimoPago, miercoles, ultimoPago: ultimoPago), ultimoPago);
    });

    test('desde el último pago sin ningún pago registrado: null, "desde siempre"', () {
      expect(inicioDePeriodo(PeriodoResumen.desdeUltimoPago, miercoles), isNull);
    });
  });

  group('tocaPedirHoy', () {
    final miercoles = DateTime(2026, 10, 7, 9);
    test('el día de hoy, con o sin acento y mayúsculas', () {
      expect(tocaPedirHoy('Miércoles', miercoles), isTrue);
      expect(tocaPedirHoy('miercoles ', miercoles), isTrue);
    });
    test('otro día o sin día cargado: no', () {
      expect(tocaPedirHoy('Martes', miercoles), isFalse);
      expect(tocaPedirHoy(null, miercoles), isFalse);
    });
    test('sábado y domingo', () {
      expect(tocaPedirHoy('Sábado', DateTime(2026, 10, 10)), isTrue);
      expect(tocaPedirHoy('Domingo', DateTime(2026, 10, 11)), isTrue);
    });
  });
}
