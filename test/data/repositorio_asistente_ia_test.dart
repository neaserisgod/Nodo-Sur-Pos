// El asistente con IA contra una base real: los datos que ve y que lo confirmado se vuelva a validar antes de escribir.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_asistente_ia.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/asistente_ia.dart';
import 'package:la_plazoleta/domain/turnos.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int corte;

  // Lunes 12 de octubre de 2026 a las 9: con el horario de arranque, de 9 a 20.
  final ahora = DateTime(2026, 10, 12, 9);
  DateTime a(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Caro'));
    corte = await crearServicio(db, nombre: 'Corte', precioCentavos: 800000, duracionMinutos: 30, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  Future<ServicioIa> servicio() async => (await datosParaAsistenteIa(db, ahora: ahora)).servicios.single;

  test('ve los servicios, los turnos y los huecos del día', () async {
    await crearTurno(db, servicioId: corte, inicio: a(10), nombreCliente: 'Juana', telefono: '2944111111', usuarioId: usuarioId);
    final d = await datosParaAsistenteIa(db, ahora: ahora);
    expect(d.servicios.single.nombre, 'Corte');
    expect(d.turnos.single.cliente, 'Juana');
    final hoy = d.libres[DateTime(2026, 10, 12)]!;
    expect(hoy, contains(a(9)));
    expect(hoy, isNot(contains(a(10))));
    expect(d.cajaAbierta, isFalse);
    expect(textoDatosIa(d), isNot(contains('2944111111')));
  });

  test('dar un turno confirmado lo anota; si el horario se ocupó, no', () async {
    final s = await servicio();
    final aviso = await ejecutarAccionIa(db, DarTurnoIa(servicio: s, inicio: a(11), cliente: 'Ana'), usuarioId: usuarioId, ahora: ahora);
    expect(aviso, contains('Ana'));
    expect((await turnosDelDia(db, a(0))).single.turno.nombreCliente, 'Ana');

    expect(
      () => ejecutarAccionIa(db, DarTurnoIa(servicio: s, inicio: a(11, 15), cliente: 'Eva'), usuarioId: usuarioId, ahora: ahora),
      throwsArgumentError,
    );
  });

  test('mover y cancelar; con seña, cancelar se deja para la Agenda', () async {
    final id = await crearTurno(db, servicioId: corte, inicio: a(10), nombreCliente: 'Juana', usuarioId: usuarioId);
    final turno = (await datosParaAsistenteIa(db, ahora: ahora)).turnos.single;
    await ejecutarAccionIa(db, MoverTurnoIa(turno: turno, inicio: a(10, 15)), usuarioId: usuarioId, ahora: ahora);
    expect((await turnosDelDia(db, a(0))).single.inicio, a(10, 15));

    await ejecutarAccionIa(db, CancelarTurnoIa(turno: turno), usuarioId: usuarioId, ahora: ahora);
    final t = await (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();
    expect(t.estado, EstadoTurno.cancelado.clave);

    final conSena = await crearTurno(db, servicioId: corte, inicio: a(12), nombreCliente: 'Ana', usuarioId: usuarioId, senaCentavos: 100000);
    final tConSena = (await datosParaAsistenteIa(db, ahora: ahora)).turnos.firstWhere((t) => t.id == conSena);
    expect(() => ejecutarAccionIa(db, CancelarTurnoIa(turno: tConSena), usuarioId: usuarioId, ahora: ahora), throwsArgumentError);
  });

  test('un gasto sin caja abierta no se anota', () async {
    expect(
      () => ejecutarAccionIa(db, const GastoIa(montoCentavos: 100000, motivo: 'Café', porMercadoPago: false), usuarioId: usuarioId, ahora: ahora),
      throwsArgumentError,
    );
  });
}
