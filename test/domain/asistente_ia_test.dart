// Asistente con IA de Nodo Sur Servicios (El dueño, 2026-10-16: "responde y actúa"). Lo que importa: que nada de lo que
// propone la IA llegue a la persona sin validar contra los datos (ids, horas pasadas, servicios inventados, caja cerrada).
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/asistente_ia.dart';
import 'package:la_plazoleta/domain/turnos.dart';

void main() {
  // Viernes 16 de octubre de 2026, 11:00.
  final ahora = DateTime(2026, 10, 16, 11);
  const corte = ServicioIa(id: 1, nombre: 'Corte', precioCentavos: 800000, duracionMin: 30);
  const sinDuracion = ServicioIa(id: 2, nombre: 'Consulta', precioCentavos: 0, duracionMin: 0);
  final pendiente = TurnoIa(id: 10, inicio: DateTime(2026, 10, 16, 15), duracionMin: 30, servicio: 'Corte', cliente: 'Juana', estado: EstadoTurno.confirmado);
  final atendido = TurnoIa(id: 11, inicio: DateTime(2026, 10, 16, 9), duracionMin: 30, servicio: 'Corte', cliente: 'Ana', estado: EstadoTurno.atendido);
  final pasado = TurnoIa(id: 12, inicio: DateTime(2026, 10, 16, 10), duracionMin: 30, servicio: 'Corte', cliente: 'Eva', estado: EstadoTurno.confirmado);

  DatosIa datos({bool cajaAbierta = true}) => DatosIa(
        negocio: 'Barbería Sur',
        ahora: ahora,
        horario: HorarioAtencion.porDefecto,
        servicios: const [corte, sinDuracion],
        turnos: [pendiente, atendido, pasado],
        libres: {
          DateTime(2026, 10, 16): [DateTime(2026, 10, 16, 12), DateTime(2026, 10, 16, 12, 15), DateTime(2026, 10, 16, 17)],
        },
        cajaAbierta: cajaAbierta,
        hoy: (centavos: 1600000, cobros: 2),
        mes: (centavos: 20000000, cobros: 25),
        mesAnterior: (centavos: 30000000, cobros: 40),
        serviciosDelMes: const {'Corte': 25},
      );

  group('leerRespuestaIa', () {
    test('un turno nuevo válido pasa, con el servicio de la lista', () {
      final r = leerRespuestaIa({
        'respuesta': 'Te lo anoto',
        'acciones': [
          {'tipo': 'dar_turno', 'servicio_id': 1, 'inicio': '2026-10-16T12:15', 'cliente': ' Juana '},
        ],
      }, datos());
      expect(r.texto, 'Te lo anoto');
      final a = r.acciones.single as DarTurnoIa;
      expect(a.servicio.nombre, 'Corte');
      expect(a.inicio, DateTime(2026, 10, 16, 12, 15));
      expect(a.cliente, 'Juana');
      expect(r.descartadas, 0);
    });

    test('se descarta un servicio inventado, uno sin duración, una hora pasada, una fecha imposible o sin nombre', () {
      final r = leerRespuestaIa({
        'respuesta': 'ok',
        'acciones': [
          {'tipo': 'dar_turno', 'servicio_id': 99, 'inicio': '2026-10-16T12:00', 'cliente': 'Juana'},
          {'tipo': 'dar_turno', 'servicio_id': 2, 'inicio': '2026-10-16T12:00', 'cliente': 'Juana'},
          {'tipo': 'dar_turno', 'servicio_id': 1, 'inicio': '2026-10-16T10:00', 'cliente': 'Juana'},
          {'tipo': 'dar_turno', 'servicio_id': 1, 'inicio': '2026-02-31T10:00', 'cliente': 'Juana'},
          {'tipo': 'dar_turno', 'servicio_id': 1, 'inicio': '2026-10-17T10:00', 'cliente': ''},
        ],
      }, datos());
      expect(r.acciones, isEmpty);
      expect(r.descartadas, 5);
    });

    test('solo se mueve o cancela un turno pendiente que no pasó', () {
      final r = leerRespuestaIa({
        'respuesta': 'ok',
        'acciones': [
          {'tipo': 'cancelar_turno', 'turno_id': 10},
          {'tipo': 'cancelar_turno', 'turno_id': 11}, // atendido
          {'tipo': 'cancelar_turno', 'turno_id': 12}, // ya pasó
          {'tipo': 'cancelar_turno', 'turno_id': 77}, // no existe
          {'tipo': 'mover_turno', 'turno_id': 10, 'inicio': '2026-10-16T17:00'},
          {'tipo': 'mover_turno', 'turno_id': 10, 'inicio': '2026-10-16T15:00'}, // a la misma hora
        ],
      }, datos());
      expect(r.acciones.length, 2);
      expect((r.acciones[0] as CancelarTurnoIa).turno.id, 10);
      expect((r.acciones[1] as MoverTurnoIa).inicio, DateTime(2026, 10, 16, 17));
      expect(r.descartadas, 4);
    });

    test('el gasto pasa a centavos y necesita la caja abierta', () {
      final json = {
        'respuesta': 'ok',
        'acciones': [
          {'tipo': 'gasto', 'pesos': 1500, 'motivo': 'Café', 'medio': 'mercadopago'},
          {'tipo': 'gasto', 'pesos': -5, 'motivo': 'x'},
          {'tipo': 'gasto', 'pesos': 100, 'motivo': ''},
        ],
      };
      final abierta = leerRespuestaIa(json, datos());
      final g = abierta.acciones.single as GastoIa;
      expect(g.montoCentavos, 150000);
      expect(g.porMercadoPago, isTrue);
      expect(leerRespuestaIa(json, datos(cajaAbierta: false)).acciones, isEmpty);
    });

    test('ir a una pantalla conocida; una desconocida se descarta', () {
      final r = leerRespuestaIa({
        'respuesta': 'Mirá',
        'acciones': [
          {'tipo': 'ir_a', 'pantalla': 'agenda'},
          {'tipo': 'ir_a', 'pantalla': 'productos'},
          {'tipo': 'borrar_todo'},
        ],
      }, datos());
      expect((r.acciones.single as IrAIa).pantalla, PantallaIa.agenda);
      expect(r.descartadas, 2);
    });

    test('una respuesta rota no rompe: se dice que no contestó', () {
      expect(leerRespuestaIa('hola', datos()).texto, contains('no contestó'));
      expect(leerRespuestaIa({'acciones': 'x'}, datos()).acciones, isEmpty);
    });
  });

  group('textoDatosIa', () {
    test('lleva servicios, turnos con id, huecos como tramos y cobros; nunca teléfonos', () {
      final t = textoDatosIa(datos());
      expect(t, contains('1: Corte'));
      expect(t, contains('10: vie 16/10 15:00'));
      expect(t, contains('Juana'));
      expect(t, contains('12:00 a 12:15, 17:00'));
      expect(t, contains('Caja: abierta'));
      expect(t, contains('Corte (25)'));
      expect(t, contains('dom: cerrado'));
    });

    test('el pedido lleva solo las últimas preguntas', () {
      final antes = [for (var i = 0; i < 5; i++) (pregunta: 'p$i', respuesta: 'r$i')];
      final p = armarPedidoIa('¿y mañana?', datos(), antes: antes);
      expect(p, isNot(contains('p1')));
      expect(p, contains('p2'));
      expect(p, contains('p4'));
      expect(p.trimRight(), endsWith('Pregunta: ¿y mañana?'));
    });
  });

  test('tramosLibres junta los horarios seguidos', () {
    final d = DateTime(2026, 10, 16);
    final tramos = tramosLibres([d.add(const Duration(hours: 9)), d.add(const Duration(hours: 9, minutes: 15)), d.add(const Duration(hours: 14))], pasoMin: 15);
    expect(tramos.length, 2);
    expect(tramos.first.hasta, d.add(const Duration(hours: 9, minutes: 15)));
  });

  test('describirAccionIa lo dice la app, con fecha y hora', () {
    expect(
      describirAccionIa(DarTurnoIa(servicio: corte, inicio: DateTime(2026, 10, 17, 10), cliente: 'Juana')),
      'Turno para Juana: Corte, sáb 17/10 10:00',
    );
  });
}
