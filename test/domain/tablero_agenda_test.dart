// El tablero de arriba de la Agenda (`domain/tablero_agenda.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/tablero_agenda.dart';

TurnoDelTablero _t(int h, int m, {int dur = 30, bool ocupa = true, bool atendido = false, int precio = 0, int sena = 0, int faltas = 0}) =>
    TurnoDelTablero(
      inicio: DateTime(2026, 10, 13, h, m),
      duracionMin: dur,
      cliente: 'C$h$m',
      servicio: 'Corte',
      ocupa: ocupa,
      atendido: atendido,
      precioCentavos: precio,
      senaCentavos: sena,
      faltas: faltas,
    );

void main() {
  final ahora = DateTime(2026, 10, 13, 14, 10);

  group('próximo turno', () {
    test('el que está pasando gana al que viene', () {
      final p = proximoTurno([_t(16, 0), _t(14, 0), _t(15, 0)], ahora)!;
      expect(p.turno.inicio.hour, 14);
      expect(p.enCurso, isTrue);
    });
    test('sin uno en curso, el próximo en empezar; los cobrados, cancelados y terminados no cuentan', () {
      final p = proximoTurno([_t(13, 0), _t(14, 0, atendido: true), _t(14, 30, ocupa: false), _t(15, 0)], ahora)!;
      expect(p.turno.inicio.hour, 15);
      expect(p.enCurso, isFalse);
    });
    test('sin turnos por delante: null', () => expect(proximoTurno([_t(9, 0)], ahora), isNull));
  });

  test('cuánto falta', () {
    expect(textoFaltaPara(DateTime(2026, 10, 13, 14, 30), ahora), 'en 20 min');
    expect(textoFaltaPara(DateTime(2026, 10, 13, 15, 10), ahora), 'en 1 h');
    expect(textoFaltaPara(DateTime(2026, 10, 13, 15, 25), ahora), 'en 1 h 15 min');
    expect(textoFaltaPara(DateTime(2026, 10, 13, 14, 0), ahora), 'ahora');
  });

  test('por cobrar: precio menos seña de los que siguen en pie, nunca negativo', () {
    final turnos = [
      _t(15, 0, precio: 1400000, sena: 400000), // 10.000
      _t(16, 0, precio: 1800000), // 18.000
      _t(10, 0, precio: 1400000, atendido: true), // ya cobrado
      _t(11, 0, precio: 1400000, ocupa: false), // no vino
      _t(17, 0, precio: 500000, sena: 900000), // seña mayor al precio de hoy: 0
    ];
    expect(porCobrarCentavos(turnos), 2800000);
    expect(turnosQueFaltan(turnos), 3);
  });

  test('quien viene hoy y ya faltó', () {
    final r = conFaltasPrevias([_t(15, 0, faltas: 2), _t(16, 0), _t(9, 0, faltas: 1), _t(17, 0, faltas: 1, atendido: true)], ahora);
    expect(r.map((t) => t.inicio.hour), [15]);
  });

  test('huecos: el comienzo de cada tramo seguido', () {
    DateTime h(int hh, int mm) => DateTime(2026, 10, 13, hh, mm);
    expect(comienzosDeHuecos([h(10, 30), h(10, 0), h(10, 15), h(15, 0), h(15, 15), h(18, 0)], pasoMin: 15), [h(10, 0), h(15, 0), h(18, 0)]);
    expect(comienzosDeHuecos([], pasoMin: 15), isEmpty);
  });

  group('texto para compartir', () {
    final hoy = DateTime(2026, 10, 13); // martes
    test('hoy, mañana y el día con nombre; hasta 4 horarios por día; los días sin huecos no aparecen', () {
      final t = textoCompartirHuecos(
        negocio: 'Barbería El Faro',
        emoji: '💈',
        hoy: hoy,
        dias: [
          (dia: hoy, comienzos: [DateTime(2026, 10, 13, 15), DateTime(2026, 10, 13, 17, 30)]),
          (dia: DateTime(2026, 10, 14), comienzos: const []),
          (dia: DateTime(2026, 10, 15), comienzos: [for (var i = 9; i < 15; i++) DateTime(2026, 10, 15, i)]),
        ],
      )!;
      expect(t, startsWith('¡Me quedan lugares en Barbería El Faro! 💈'));
      expect(t, contains('Hoy: 15, 17:30 h'));
      expect(t, isNot(contains('Mañana')));
      expect(t, contains('Jueves 15: 9, 10, 11, 12 h'));
      expect(t, contains('Escribime por WhatsApp'));
    });
    test('sin huecos no hay nada que compartir', () {
      expect(textoCompartirHuecos(negocio: 'X', emoji: '💈', hoy: hoy, dias: [(dia: hoy, comienzos: const [])]), isNull);
    });
    test('emoji por rubro', () {
      expect(emojiDeRubro('unas'), '💅');
      expect(emojiDeRubro('otro'), '📅');
    });
  });
}
