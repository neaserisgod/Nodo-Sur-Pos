// Turnos de la agenda (`REGLAS-NEGOCIO.md` §21) contra una base de verdad.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import 'package:la_plazoleta/domain/agenda.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int corte;
  final lunes10 = DateTime(2026, 10, 12, 10);

  setUp(() async {
    db = baseDeTest();
    usuarioId = (await db.select(db.usuarios).get()).first.id;
    corte = await crearServicio(db, nombre: 'Corte', precioCentavos: 1200000, duracionMinutos: 45, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  test('anotar un turno lo deja confirmado, con la duración del servicio, y con teléfono guarda al cliente', () async {
    final id = await crearTurno(db, nombreCliente: 'Sofi', telefono: '2944 123456', servicioId: corte, inicio: lunes10, usuarioId: usuarioId);
    final t = (await turnosDelDia(db, lunes10)).single;
    expect(t.turno.id, id);
    expect(t.estado, EstadoTurno.confirmado);
    expect(t.turno.duracionMinutos, 45);
    expect(t.fin, DateTime(2026, 10, 12, 10, 45));
    expect(t.servicio?.nombre, 'Corte');
    expect(t.turno.globalId, isNotNull, reason: 'viaja por la sync');
    final cliente = await (db.select(db.clientes)..where((c) => c.telefono.equals('2944 123456'))).getSingle();
    expect(cliente.nombre, 'Sofi');
    expect(t.turno.clienteId, cliente.id);

    // El mismo teléfono no crea otro cliente.
    await crearTurno(db, nombreCliente: 'Sofía', telefono: '2944 123456', servicioId: corte, inicio: lunes10.add(const Duration(days: 1)), usuarioId: usuarioId);
    expect(await (db.select(db.clientes)..where((c) => c.telefono.equals('2944 123456'))).get(), hasLength(1));
  });

  test('sin teléfono alcanza con el nombre y no crea cliente', () async {
    await crearTurno(db, nombreCliente: 'Juan', servicioId: corte, inicio: lunes10, usuarioId: usuarioId);
    expect((await turnosDelDia(db, lunes10)).single.turno.clienteId, isNull);
  });

  test('un producto que no es servicio no se agenda', () async {
    final yerba = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Yerba'));
    expect(() => crearTurno(db, nombreCliente: 'X', servicioId: yerba, inicio: lunes10, usuarioId: usuarioId), throwsArgumentError);
  });

  test('sobreturno: avisa si se pisa con otro del mismo profesional, no con el de otro', () async {
    final otro = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Nico'));
    await crearTurno(db, nombreCliente: 'Sofi', servicioId: corte, profesionalId: usuarioId, inicio: lunes10, usuarioId: usuarioId);
    expect(await esSobreturno(db, inicio: DateTime(2026, 10, 12, 10, 30), duracionMinutos: 30, profesionalId: usuarioId), isTrue);
    expect(await esSobreturno(db, inicio: DateTime(2026, 10, 12, 10, 30), duracionMinutos: 30, profesionalId: otro), isFalse);
    expect(await esSobreturno(db, inicio: DateTime(2026, 10, 12, 10, 45), duracionMinutos: 30, profesionalId: usuarioId), isFalse);
  });

  test('cancelado y no vino liberan el horario; no vino suma faltas al cliente', () async {
    final a = await crearTurno(db, nombreCliente: 'Sofi', telefono: '111', servicioId: corte, inicio: lunes10, usuarioId: usuarioId);
    await marcarTurno(db, a, EstadoTurno.noVino);
    expect(await ocupadosDelDia(db, lunes10), isEmpty);
    final b = await crearTurno(db, nombreCliente: 'Sofi', telefono: '111', servicioId: corte, inicio: lunes10, usuarioId: usuarioId);
    await cancelarTurno(db, b);
    expect(await ocupadosDelDia(db, lunes10), isEmpty);
    final c = await crearTurno(db, nombreCliente: 'Sofi', telefono: '111', servicioId: corte, inicio: lunes10.add(const Duration(days: 7)), usuarioId: usuarioId);
    final turnoC = (await turnosDelDia(db, lunes10.add(const Duration(days: 7)))).single;
    expect(turnoC.turno.id, c);
    expect(turnoC.faltas, 1, reason: 'faltó una vez (cancelar no cuenta)');
  });

  test('cobrado queda con su venta y ya no se cancela', () async {
    final id = await crearTurno(db, nombreCliente: 'Sofi', servicioId: corte, inicio: lunes10, usuarioId: usuarioId);
    final sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final venta = await db.into(db.ventas).insert(VentasCompanion.insert(sesionCajaId: sesion, usuarioId: usuarioId, subtotalCentavos: 1200000, totalCentavos: 1200000));
    await marcarTurnoCobrado(db, id, ventaId: venta);
    final t = (await turnosDelDia(db, lunes10)).single;
    expect(t.estado, EstadoTurno.cobrado);
    expect(t.turno.ventaId, venta);
    expect(() => cancelarTurno(db, id), throwsArgumentError);
  });

  test('la agenda del negocio arranca con el horario por defecto y cada 15 minutos', () async {
    final c = await configuracionAgenda(db);
    expect(c.intervaloMinutos, 15);
    expect(c.horario.franjasDe(DateTime.sunday), isEmpty);
    await configurarAgenda(db, intervaloMinutos: 30, horario: HorarioAtencion({DateTime.sunday: [(desde: 600, hasta: 840)]}));
    final d = await configuracionAgenda(db);
    expect(d.intervaloMinutos, 30);
    expect(d.horario.franjasDe(DateTime.sunday), [(desde: 600, hasta: 840)]);
  });

  test('un turno viaja por la sync con su servicio y su profesional', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final otra = baseDeTest();
    addTearDown(() async {
      await otra.close();
      establecerIdDispositivo('desktop');
    });
    await crearTurno(db, nombreCliente: 'Sofi', servicioId: corte, profesionalId: usuarioId, inicio: lunes10, usuarioId: usuarioId);
    for (final tabla in ['usuarios', 'productos', 'turnos']) {
      await aplicarCambios(otra, tabla: tabla, filas: await cambiosDesde(db, tabla: tabla, desde: 0));
    }
    final t = (await turnosDelDia(otra, lunes10)).single;
    expect(t.turno.nombreCliente, 'Sofi');
    expect(t.servicio?.nombre, 'Corte');
    expect(t.profesional, isNotNull);
  });
}
