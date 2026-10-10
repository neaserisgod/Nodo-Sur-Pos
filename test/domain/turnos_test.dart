import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/turnos.dart';

// Regla 21: turnos, agenda y seña.
TurnoParaAgenda _t(int id, String hora, int minutos, {int? prof, EstadoTurno estado = EstadoTurno.confirmado}) {
  final p = hora.split(':');
  return TurnoParaAgenda(
    id: id,
    profesionalId: prof,
    inicio: DateTime(2026, 10, 12, int.parse(p[0]), int.parse(p[1])), // lunes
    duracionMinutos: minutos,
    estado: estado,
  );
}

DateTime _h(String hora) {
  final p = hora.split(':');
  return DateTime(2026, 10, 12, int.parse(p[0]), int.parse(p[1]));
}

void main() {
  group('estados', () {
    test('las claves se guardan en la base y no cambian', () {
      expect(EstadoTurno.values.map((e) => e.clave), ['pendiente', 'confirmado', 'llego', 'cobrado', 'novino', 'cancelado']);
      expect(EstadoTurno.desdeClave('llego'), EstadoTurno.llego);
      expect(EstadoTurno.desdeClave('cualquiera'), isNull);
    });

    test('cancelado y no vino dejan libre el horario; los terminados no cambian más', () {
      expect(EstadoTurno.cancelado.ocupaHorario, isFalse);
      expect(EstadoTurno.noVino.ocupaHorario, isFalse);
      expect(EstadoTurno.cobrado.ocupaHorario, isTrue);
      expect(puedePasar(EstadoTurno.sinConfirmar, EstadoTurno.confirmado), isTrue);
      expect(puedePasar(EstadoTurno.confirmado, EstadoTurno.llego), isTrue);
      expect(puedePasar(EstadoTurno.llego, EstadoTurno.cobrado), isTrue);
      expect(puedePasar(EstadoTurno.confirmado, EstadoTurno.noVino), isTrue);
      expect(puedePasar(EstadoTurno.cobrado, EstadoTurno.cancelado), isFalse);
      expect(puedePasar(EstadoTurno.noVino, EstadoTurno.confirmado), isFalse);
      expect(puedePasar(EstadoTurno.cancelado, EstadoTurno.llego), isFalse);
      expect(puedePasar(EstadoTurno.llego, EstadoTurno.sinConfirmar), isFalse, reason: 'no se vuelve atrás');
    });
  });

  group('superposición (un profesional no tiene dos turnos que se pisan)', () {
    final otros = [_t(1, '10:00', 60, prof: 1), _t(2, '12:00', 30, prof: 2), _t(3, '14:00', 60, prof: 1, estado: EstadoTurno.cancelado)];

    test('con varios profesionales, solo choca con los del mismo', () {
      expect(conQuienChoca(inicio: _h('10:30'), duracionMinutos: 30, profesionalId: 1, otros: otros, variosProfesionales: true)?.id, 1);
      expect(conQuienChoca(inicio: _h('10:30'), duracionMinutos: 30, profesionalId: 2, otros: otros, variosProfesionales: true), isNull);
    });

    test('pegados no se pisan: el que empieza cuando termina el otro está bien', () {
      expect(conQuienChoca(inicio: _h('11:00'), duracionMinutos: 60, profesionalId: 1, otros: otros, variosProfesionales: true), isNull);
      expect(conQuienChoca(inicio: _h('09:00'), duracionMinutos: 60, profesionalId: 1, otros: otros, variosProfesionales: true), isNull);
      expect(conQuienChoca(inicio: _h('09:30'), duracionMinutos: 31, profesionalId: 1, otros: otros, variosProfesionales: true)?.id, 1);
    });

    test('sin varios profesionales la agenda es una sola: choca con cualquiera', () {
      expect(conQuienChoca(inicio: _h('12:15'), duracionMinutos: 30, profesionalId: null, otros: otros, variosProfesionales: false)?.id, 2);
    });

    test('un cancelado no ocupa, y al mover un turno no choca consigo mismo', () {
      expect(conQuienChoca(inicio: _h('14:00'), duracionMinutos: 60, profesionalId: 1, otros: otros, variosProfesionales: true), isNull);
      expect(conQuienChoca(inicio: _h('10:15'), duracionMinutos: 60, profesionalId: 1, otros: otros, variosProfesionales: true, excepto: 1), isNull);
    });
  });

  group('horario de atención (una franja por día)', () {
    test('de fábrica: lunes a viernes de 9 a 20, sábado de 9 a 14, domingo cerrado', () {
      final h = HorarioSemana.porDefecto;
      expect(h.franjaDe(DateTime(2026, 10, 12)), const FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200)); // lunes
      expect(h.franjaDe(DateTime(2026, 10, 17)), const FranjaHoraria(desdeMinutos: 540, hastaMinutos: 840)); // sábado
      expect(h.franjaDe(DateTime(2026, 10, 18)), isNull); // domingo
    });

    test('se guarda como texto y vuelve igual; un texto roto es el de fábrica', () {
      final h = HorarioSemana.porDefecto.conDia(DateTime.sunday, const FranjaHoraria(desdeMinutos: 600, hastaMinutos: 780));
      expect(HorarioSemana.desdeTexto(h.aTexto()), h);
      expect(HorarioSemana.desdeTexto('no es json'), HorarioSemana.porDefecto);
      expect(HorarioSemana.desdeTexto(''), HorarioSemana.porDefecto);
    });

    test('una franja tiene que empezar antes de terminar', () {
      expect(() => FranjaHoraria(desdeMinutos: 600, hastaMinutos: 600).validar(), throwsArgumentError);
    });

    test('dentro de horario: el turno entero entra en la franja del día', () {
      final h = HorarioSemana.porDefecto;
      expect(dentroDeHorario(h, inicio: _h('19:00'), duracionMinutos: 60), isTrue);
      expect(dentroDeHorario(h, inicio: _h('19:30'), duracionMinutos: 60), isFalse);
      expect(dentroDeHorario(h, inicio: _h('08:30'), duracionMinutos: 30), isFalse);
      expect(dentroDeHorario(h, inicio: DateTime(2026, 10, 18, 10), duracionMinutos: 30), isFalse, reason: 'domingo cerrado');
    });
  });

  group('huecos libres de un día (lo que muestra la agenda)', () {
    test('entre la franja y los turnos, de al menos 30 minutos', () {
      final turnos = [_t(1, '10:00', 60), _t(2, '11:15', 45), _t(3, '18:00', 60)];
      final huecos = huecosLibres(dia: DateTime(2026, 10, 12), horario: HorarioSemana.porDefecto, turnos: turnos);
      expect(huecos.map((h) => '${h.desde.hour}:${h.desde.minute}-${h.hasta.hour}:${h.hasta.minute}'), ['9:0-10:0', '12:0-18:0', '19:0-20:0']);
    });

    test('los cancelados no tapan nada y un día cerrado no tiene huecos', () {
      final turnos = [_t(1, '09:00', 660, estado: EstadoTurno.cancelado)];
      expect(huecosLibres(dia: DateTime(2026, 10, 12), horario: HorarioSemana.porDefecto, turnos: turnos), hasLength(1));
      expect(huecosLibres(dia: DateTime(2026, 10, 18), horario: HorarioSemana.porDefecto, turnos: const []), isEmpty);
    });
  });

  group('seña sugerida', () {
    test('de fábrica: algunos servicios, 30 %, hacia arriba a la centena', () {
      const c = ConfigSena.porDefecto;
      expect(c.modo, ModoSena.algunos);
      expect(c.siNoViene, SiNoViene.pierde);
      expect(senaSugerida(precioCentavos: 1850000, config: c, servicioPideSena: true), 560000); // 5.550 → 5.600
      expect(senaSugerida(precioCentavos: 1850000, config: c, servicioPideSena: false), 0);
    });

    test('todos, nunca y monto fijo (nunca más que el precio)', () {
      const todos = ConfigSena(modo: ModoSena.todos, esPorcentaje: false, valor: 500000, siNoViene: SiNoViene.devuelve);
      expect(senaSugerida(precioCentavos: 1000000, config: todos, servicioPideSena: false), 500000);
      expect(senaSugerida(precioCentavos: 300000, config: todos, servicioPideSena: false), 300000);
      const nunca = ConfigSena(modo: ModoSena.nunca, esPorcentaje: true, valor: 3000, siNoViene: SiNoViene.pierde);
      expect(senaSugerida(precioCentavos: 1000000, config: nunca, servicioPideSena: true), 0);
    });

    test('se guarda como texto y vuelve igual; un texto roto es el de fábrica', () {
      const c = ConfigSena(modo: ModoSena.todos, esPorcentaje: false, valor: 500000, siNoViene: SiNoViene.devuelve);
      expect(ConfigSena.desdeTexto(c.aTexto()), c);
      expect(ConfigSena.desdeTexto('{roto'), ConfigSena.porDefecto);
    });

    test('si no vino: con "se pierde" no se devuelve nada; con "se devuelve", toda la seña', () {
      expect(senaADevolver(senaCentavos: 500000, estadoFinal: EstadoTurno.noVino, siNoViene: SiNoViene.pierde), 0);
      expect(senaADevolver(senaCentavos: 500000, estadoFinal: EstadoTurno.noVino, siNoViene: SiNoViene.devuelve), 500000);
      expect(senaADevolver(senaCentavos: 500000, estadoFinal: EstadoTurno.cancelado, siNoViene: SiNoViene.pierde), 500000,
          reason: 'cancelar con aviso siempre devuelve (El dueño, 2026-10-10)');
    });
  });
}
