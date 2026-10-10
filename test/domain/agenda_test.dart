import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/agenda.dart';

/// Agenda de un negocio de servicios (`REGLAS-NEGOCIO.md` §21): horario de atención, horarios libres, sobreturnos y el
/// enlace a Google Calendar.
void main() {
  // 2026-10-12 es lunes.
  final lunes = DateTime(2026, 10, 12);

  group('horario de atención', () {
    test('por defecto: lunes a sábado de 9 a 19, domingo cerrado', () {
      final h = HorarioAtencion.porDefecto;
      expect(h.franjasDe(DateTime.monday), [(desde: 9 * 60, hasta: 19 * 60)]);
      expect(h.franjasDe(DateTime.saturday), [(desde: 9 * 60, hasta: 19 * 60)]);
      expect(h.franjasDe(DateTime.sunday), isEmpty);
    });

    test('va y vuelve como JSON, con días cortados al mediodía', () {
      final h = HorarioAtencion({
        DateTime.monday: [(desde: 9 * 60, hasta: 13 * 60), (desde: 16 * 60, hasta: 20 * 60)],
        DateTime.tuesday: [(desde: 10 * 60, hasta: 18 * 60)],
      });
      final vuelta = HorarioAtencion.desdeJson(h.aJson());
      expect(vuelta.franjasDe(DateTime.monday), h.franjasDe(DateTime.monday));
      expect(vuelta.franjasDe(DateTime.tuesday), h.franjasDe(DateTime.tuesday));
      expect(vuelta.franjasDe(DateTime.wednesday), isEmpty);
    });

    test('un JSON roto o vacío es el horario por defecto: la agenda nunca queda sin horarios por un dato raro', () {
      expect(HorarioAtencion.desdeJson(null).franjasDe(DateTime.monday), HorarioAtencion.porDefecto.franjasDe(DateTime.monday));
      expect(HorarioAtencion.desdeJson('{no es json').franjasDe(DateTime.friday), HorarioAtencion.porDefecto.franjasDe(DateTime.friday));
    });
  });

  group('horarios libres', () {
    final horario = HorarioAtencion({DateTime.monday: [(desde: 9 * 60, hasta: 12 * 60)]});

    List<String> libres({int duracion = 30, int intervalo = 15, List<({DateTime inicio, DateTime fin})> ocupados = const [], DateTime? ahora}) => [
          for (final h in horariosLibres(horario: horario, dia: lunes, duracionMinutos: duracion, intervaloMinutos: intervalo, ocupados: ocupados, ahora: ahora))
            '${h.hour}:${h.minute.toString().padLeft(2, '0')}',
        ];

    test('cada 15 minutos, sin pasarse del cierre', () {
      final l = libres(duracion: 60);
      expect(l.first, '9:00');
      expect(l[1], '9:15');
      expect(l.last, '11:00', reason: 'un turno de una hora que empieza 11:15 termina después de las 12');
    });

    test('cada 30 minutos si el negocio lo eligió', () {
      expect(libres(intervalo: 30), ['9:00', '9:30', '10:00', '10:30', '11:00', '11:30']);
    });

    test('saltea lo ocupado y lo que se pisaría con lo ocupado', () {
      final l = libres(ocupados: [(inicio: DateTime(2026, 10, 12, 10), fin: DateTime(2026, 10, 12, 10, 45))]);
      expect(l, isNot(contains('9:45')), reason: '9:45 a 10:15 se pisa con el de las 10');
      expect(l, contains('9:30'));
      expect(l, isNot(contains('10:30')));
      expect(l, contains('10:45'));
    });

    test('hoy no ofrece lo que ya pasó', () {
      final l = libres(intervalo: 30, ahora: DateTime(2026, 10, 12, 10, 10));
      expect(l.first, '10:30');
    });

    test('un día cerrado no tiene horarios', () {
      expect(horariosLibres(horario: horario, dia: lunes.add(const Duration(days: 6)), duracionMinutos: 30, intervaloMinutos: 15, ocupados: const []), isEmpty);
    });

    test('un intervalo o una duración inválidos no rompen: no hay horarios', () {
      expect(libres(intervalo: 0), isEmpty);
      expect(libres(duracion: 0), isEmpty);
    });
  });

  test('sobreturno: se pisa si se cruzan, no si uno termina justo cuando empieza el otro', () {
    final a = (inicio: DateTime(2026, 10, 12, 10), fin: DateTime(2026, 10, 12, 11));
    expect(seSuperponen(a, (inicio: DateTime(2026, 10, 12, 10, 30), fin: DateTime(2026, 10, 12, 11, 30))), isTrue);
    expect(seSuperponen(a, (inicio: DateTime(2026, 10, 12, 11), fin: DateTime(2026, 10, 12, 12))), isFalse);
    expect(seSuperponen(a, (inicio: DateTime(2026, 10, 12, 9), fin: DateTime(2026, 10, 12, 10))), isFalse);
  });

  test('el enlace a Google Calendar lleva título, horario en hora de Argentina y detalle', () {
    final url = Uri.parse(urlGoogleCalendar(
      titulo: 'Corte · Sofi',
      inicio: DateTime(2026, 10, 12, 10),
      fin: DateTime(2026, 10, 12, 10, 45),
      detalle: 'Estudio Lila',
    ));
    expect(url.host, 'calendar.google.com');
    expect(url.queryParameters['action'], 'TEMPLATE');
    expect(url.queryParameters['text'], 'Corte · Sofi');
    expect(url.queryParameters['dates'], '20261012T100000/20261012T104500');
    expect(url.queryParameters['ctz'], 'America/Argentina/Buenos_Aires');
    expect(url.queryParameters['details'], 'Estudio Lila');
  });

  test('los estados de un turno se guardan con claves fijas', () {
    for (final e in EstadoTurno.values) {
      expect(EstadoTurno.desdeClave(e.clave), e);
    }
    expect(EstadoTurno.desdeClave('rara'), EstadoTurno.confirmado);
    expect(EstadoTurno.esperandoSena.ocupaHorario, isTrue);
    expect(EstadoTurno.cancelado.ocupaHorario, isFalse);
    expect(EstadoTurno.noVino.ocupaHorario, isFalse);
  });
}
