// Turnos (`REGLAS-NEGOCIO.md` §21, El dueño, 2026-10-10): horarios cada 15 minutos dentro del horario de atención, el bot
// nunca ofrece uno ocupado, la seña según la configuración del negocio.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/turnos.dart';

void main() {
  // Lunes 12 de octubre de 2026.
  final lunes = DateTime(2026, 10, 12);
  const nueveADoce = HorarioAtencion({1: (desdeMin: 540, hastaMin: 720), 2: null, 3: null, 4: null, 5: null, 6: null, 7: null});

  group('horariosLibres', () {
    test('cada 15 minutos desde que abre, y el último termina justo al cerrar', () {
      final libres = horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 60, ocupados: const []);
      expect(libres.first, DateTime(2026, 10, 12, 9));
      expect(libres.last, DateTime(2026, 10, 12, 11));
      expect(libres.length, 9); // 9:00, 9:15 … 11:00
    });

    test('un día cerrado no tiene horarios', () {
      expect(horariosLibres(dia: DateTime(2026, 10, 13), horario: nueveADoce, duracionMin: 30, ocupados: const []), isEmpty);
    });

    test('no ofrece un horario que pisa un turno, pero sí el que empieza justo cuando termina', () {
      final ocupado = (inicio: DateTime(2026, 10, 12, 10), duracionMin: 60);
      final libres = horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 60, ocupados: [ocupado]);
      expect(libres, contains(DateTime(2026, 10, 12, 9)));
      expect(libres, isNot(contains(DateTime(2026, 10, 12, 9, 15))));
      expect(libres, isNot(contains(DateTime(2026, 10, 12, 10, 45))));
      expect(libres, contains(DateTime(2026, 10, 12, 11)));
    });

    test('no ofrece lo que ya pasó ni lo que está antes de la anticipación', () {
      final libres = horariosLibres(
        dia: lunes,
        horario: nueveADoce,
        duracionMin: 30,
        ocupados: const [],
        ahora: DateTime(2026, 10, 12, 9, 50),
        anticipacionMin: 60,
      );
      expect(libres.first, DateTime(2026, 10, 12, 11));
    });

    test('el paso se puede cambiar', () {
      final libres = horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 60, ocupados: const [], pasoMin: 30);
      expect(libres.map((d) => d.minute).toSet(), {0, 30});
    });

    test('un servicio más largo que el día no tiene lugar', () {
      expect(horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 240, ocupados: const []), isEmpty);
    });

    test('duración o paso en cero es un error', () {
      expect(() => horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 0, ocupados: const []), throwsArgumentError);
      expect(() => horariosLibres(dia: lunes, horario: nueveADoce, duracionMin: 30, ocupados: const [], pasoMin: 0), throwsArgumentError);
    });
  });

  group('seSolapan y fueraDeHorario', () {
    test('se pisan si se cruzan; uno a continuación del otro no', () {
      final a = (inicio: DateTime(2026, 10, 12, 10), duracionMin: 60);
      expect(seSolapan(a, (inicio: DateTime(2026, 10, 12, 10, 30), duracionMin: 60)), isTrue);
      expect(seSolapan(a, (inicio: DateTime(2026, 10, 12, 11), duracionMin: 60)), isFalse);
      expect(seSolapan(a, (inicio: DateTime(2026, 10, 12, 9), duracionMin: 60)), isFalse);
      expect(seSolapan(a, (inicio: DateTime(2026, 10, 12, 9, 30), duracionMin: 120)), isTrue);
    });

    test('fuera de horario: antes de abrir, pasado el cierre o en día cerrado', () {
      expect(fueraDeHorario((inicio: DateTime(2026, 10, 12, 8, 45), duracionMin: 30), nueveADoce), isTrue);
      expect(fueraDeHorario((inicio: DateTime(2026, 10, 12, 11, 30), duracionMin: 60), nueveADoce), isTrue);
      expect(fueraDeHorario((inicio: DateTime(2026, 10, 13, 10), duracionMin: 30), nueveADoce), isTrue);
      expect(fueraDeHorario((inicio: DateTime(2026, 10, 12, 11), duracionMin: 60), nueveADoce), isFalse);
    });
  });

  group('HorarioAtencion en JSON (el mismo formato del bot)', () {
    test('ida y vuelta', () {
      final h = HorarioAtencion.desdeJson(HorarioAtencion.porDefecto.toJson());
      expect(h.toJson(), HorarioAtencion.porDefecto.toJson());
      expect(HorarioAtencion.porDefecto.toJson()['domingo'], isNull);
      expect(HorarioAtencion.porDefecto.toJson()['lunes'], {'desde': '09:00', 'hasta': '20:00'});
    });

    test('un día roto o invertido queda cerrado; algo que no es un mapa da el de arranque', () {
      final h = HorarioAtencion.desdeJson({
        'lunes': {'desde': '18:00', 'hasta': '09:00'},
        'martes': {'desde': 'nueve', 'hasta': '18:00'},
        'miercoles': {'desde': '9:00', 'hasta': '18:00'},
      });
      expect(h.dias[1], isNull);
      expect(h.dias[2], isNull);
      expect(h.dias[3], (desdeMin: 540, hastaMin: 1080));
      expect(h.dias[7], isNull);
      expect(HorarioAtencion.desdeJson('cualquier cosa').toJson(), HorarioAtencion.porDefecto.toJson());
    });
  });

  group('seña', () {
    test('por defecto: solo los servicios que la piden, 30 %, redondeado hacia arriba al peso', () {
      const c = ConfigSena();
      expect(senaDeServicio(precioCentavos: 1800000, pideSena: true, config: c), 540000);
      expect(senaDeServicio(precioCentavos: 1800000, pideSena: false, config: c), 0);
      // 30 % de $12.345 = $3.703,50 → $3.704
      expect(senaDeServicio(precioCentavos: 1234500, pideSena: true, config: c), 370400);
    });

    test('nunca y todos', () {
      expect(senaDeServicio(precioCentavos: 1000000, pideSena: true, config: const ConfigSena(modo: ModoSena.nunca)), 0);
      expect(senaDeServicio(precioCentavos: 1000000, pideSena: false, config: const ConfigSena(modo: ModoSena.todos)), 300000);
    });

    test('monto fijo, nunca más que el precio', () {
      const c = ConfigSena(montoFijoCentavos: 500000);
      expect(senaDeServicio(precioCentavos: 2000000, pideSena: true, config: c), 500000);
      expect(senaDeServicio(precioCentavos: 300000, pideSena: true, config: c), 300000);
    });

    test('un servicio sin precio no pide seña', () {
      expect(senaDeServicio(precioCentavos: 0, pideSena: true, config: const ConfigSena()), 0);
    });

    test('al cancelar: por defecto se pierde', () {
      expect(senaADevolverAlCancelar(senaCobradaCentavos: 500000, config: const ConfigSena()), 0);
      expect(senaADevolverAlCancelar(senaCobradaCentavos: 500000, config: const ConfigSena(devolverAlCancelar: true)), 500000);
    });
  });

  group('estados', () {
    test('cancelado y no vino liberan el horario; el resto lo ocupa', () {
      expect(EstadoTurno.values.where((e) => e.ocupa), [EstadoTurno.esperandoSena, EstadoTurno.confirmado, EstadoTurno.atendido]);
      expect(EstadoTurno.desdeClave('NO_VINO'), EstadoTurno.noVino);
    });

    test('faltas', () {
      expect(textoFaltas(0), isNull);
      expect(textoFaltas(1), 'faltó 1 vez');
      expect(textoFaltas(3), 'faltó 3 veces');
    });
  });
}
