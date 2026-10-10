// La agenda de turnos contra una base de verdad (`REGLAS-NEGOCIO.md` §21): anotar, superposición, estados, seña (tomarla,
// devolverla, perderla) y cobrar un turno con su seña, con la caja cuadrando.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int usuario;
  late int otraProfesional;
  late int sesion;
  late int corte;
  final lunes = DateTime(2026, 10, 12);
  DateTime a(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

  setUp(() async {
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    otraProfesional = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Caro'));
    await configurarRubro(db, PlantillaRubro.barberia);
    corte = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, receta: const [], usuarioId: usuario);
    sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  Future<FilaTurno> turno(int id) => (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();

  Future<({int efectivo, int mp})> caja() async {
    final e = await estadoCajaEnVivo(db, sesion);
    return (efectivo: e.efectivoEsperadoCentavos, mp: e.mpEsperadoCentavos);
  }

  test('anotar desde la app: nace confirmado, con la duración del servicio, el cliente nuevo y su identidad de sync', () async {
    final id = await anotarTurno(db, cliente: 'Lauti P.', telefono: '2944 123456', servicioId: corte, inicio: a(10), usuarioId: usuario);
    final t = await turno(id);
    expect(t.estado, 'confirmado');
    expect(t.origen, 'app');
    expect(t.duracionMinutos, 30);
    expect(t.globalId, isNotNull);
    final cliente = await (db.select(db.clientes)..where((c) => c.id.equals(t.clienteId))).getSingle();
    expect((cliente.nombre, cliente.telefono), ('Lauti P.', '2944 123456'));

    // El mismo cliente, escrito distinto, no se repite.
    final otro = await anotarTurno(db, cliente: 'lauti p.', servicioId: corte, inicio: a(11), usuarioId: usuario);
    expect((await turno(otro)).clienteId, t.clienteId);

    final delDia = await turnosDelDia(db, lunes);
    expect(delDia.map((x) => x.cliente.nombre), ['Lauti P.', 'Lauti P.']);
    expect((await turnosPorDia(db, lunes, lunes.add(const Duration(days: 7))))[lunes], 2);
  });

  test('un profesional no puede tener dos turnos que se pisan; otro profesional sí puede a esa hora', () async {
    await anotarTurno(db, cliente: 'Ana', servicioId: corte, profesionalId: usuario, inicio: a(10), usuarioId: usuario);
    await expectLater(
      anotarTurno(db, cliente: 'Bea', servicioId: corte, profesionalId: usuario, inicio: a(10, 15), usuarioId: usuario),
      throwsA(isA<TurnoSuperpuesto>().having((e) => e.message, 'mensaje', contains('Ana a las 10:00'))),
    );
    await anotarTurno(db, cliente: 'Bea', servicioId: corte, profesionalId: otraProfesional, inicio: a(10, 15), usuarioId: usuario);
    await anotarTurno(db, cliente: 'Cami', servicioId: corte, profesionalId: usuario, inicio: a(10, 30), usuarioId: usuario);

    // Sin varios profesionales, la agenda es una sola.
    await configurarModulo(db, Modulo.profesionales, activo: false);
    await expectLater(anotarTurno(db, cliente: 'Dani', servicioId: corte, inicio: a(10, 20), usuarioId: usuario), throwsA(isA<TurnoSuperpuesto>()));
  });

  test('mover no choca consigo mismo, y un cancelado deja libre el horario', () async {
    final id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), usuarioId: usuario);
    await moverTurno(db, turnoId: id, inicio: a(10, 15));
    expect((await turno(id)).inicio, a(10, 15));
    await cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.cancelado, usuarioId: usuario);
    await anotarTurno(db, cliente: 'Bea', servicioId: corte, inicio: a(10, 15), usuarioId: usuario);
    await expectLater(moverTurno(db, turnoId: id, inicio: a(11)), throwsArgumentError, reason: 'un cancelado ya terminó');
  });

  test('los estados van para adelante', () async {
    final id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), usuarioId: usuario);
    await cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.llego, usuarioId: usuario);
    await expectLater(cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.confirmado, usuarioId: usuario), throwsArgumentError);
    await expectLater(cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.cobrado, usuarioId: usuario), throwsArgumentError,
        reason: 'se cobra desde Vender');
  });

  test('la seña entra a la caja como ingreso; cancelar la devuelve por la misma caja', () async {
    final id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), senaCentavos: 300000, senaEsEfectivo: false,
        sesionCajaId: sesion, usuarioId: usuario);
    expect(await caja(), (efectivo: 0, mp: 300000));
    expect(await db.select(db.ventas).get(), isEmpty, reason: 'la seña no es una venta');

    await expectLater(cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.cancelado, usuarioId: usuario), throwsArgumentError,
        reason: 'devolver necesita la caja');
    final devuelto = await cambiarEstadoTurno(db, turnoId: id, estado: EstadoTurno.cancelado, usuarioId: usuario, sesionCajaId: sesion);
    expect(devuelto, 300000);
    expect(await caja(), (efectivo: 0, mp: 0));
  });

  test('si no vino: de fábrica la seña se pierde (queda en la caja); configurado, se devuelve', () async {
    final a1 = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), senaCentavos: 300000, sesionCajaId: sesion, usuarioId: usuario);
    expect(await cambiarEstadoTurno(db, turnoId: a1, estado: EstadoTurno.noVino, usuarioId: usuario), 0);
    expect(await caja(), (efectivo: 300000, mp: 0));

    await configurarSena(db, const ConfigSena(modo: ModoSena.algunos, esPorcentaje: true, valor: 3000, siNoViene: SiNoViene.devuelve));
    final b = await anotarTurno(db, cliente: 'Bea', servicioId: corte, inicio: a(11), senaCentavos: 200000, sesionCajaId: sesion, usuarioId: usuario);
    expect(await cambiarEstadoTurno(db, turnoId: b, estado: EstadoTurno.noVino, usuarioId: usuario, sesionCajaId: sesion), 200000);
    expect(await caja(), (efectivo: 300000, mp: 0));
  });

  test('cobrar el turno: la venta es por el total, la seña es un pago que no mueve la caja de nuevo, y el turno queda cobrado', () async {
    final id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), senaCentavos: 300000, senaEsEfectivo: false,
        sesionCajaId: sesion, usuarioId: usuario);
    final linea = LineaVentaPorUnidad(productoId: '$corte', nombreProducto: 'Corte', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 1000000);
    final r = await registrarVentaSegunMedio(db, lineas: [linea], medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuario, turnoId: id);
    expect(r.totalCentavos, 1000000);

    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(r.ventaId))).get();
    expect(pagos.map((p) => (p.montoCentavos, p.canal)).toList()..sort((x, y) => x.$1.compareTo(y.$1)), [(300000, 'sena'), (700000, null)]);
    expect(await caja(), (efectivo: 700000, mp: 300000), reason: 'la seña ya estaba en MP; en efectivo entró solo el resto');
    final t = await turno(id);
    expect((t.estado, t.ventaId), ('cobrado', r.ventaId));
    expect(await aCobrarConSena(db, totalCentavos: 1000000, turnoId: id), 1000000, reason: 'cobrado: ya no hay seña pendiente');

    await expectLater(
      registrarVentaSegunMedio(db, lineas: [linea], medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuario, turnoId: id),
      throwsArgumentError,
      reason: 'un turno se cobra una sola vez',
    );
  });

  test('una seña que cubre todo deja la venta sin pagos nuevos', () async {
    final id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: a(10), senaCentavos: 1000000, sesionCajaId: sesion, usuarioId: usuario);
    final linea = LineaVentaPorUnidad(productoId: '$corte', nombreProducto: 'Corte', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 1000000);
    final r = await registrarVentaSegunMedio(db, lineas: [linea], medio: ComposicionPago.virtual, sesionCajaId: sesion, usuarioId: usuario, turnoId: id);
    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(r.ventaId))).get();
    expect(pagos.single.canal, 'sena');
    expect(await caja(), (efectivo: 1000000, mp: 0));
  });

  test('horario y seña se guardan en la configuración y vuelven iguales', () async {
    expect(await horarioActual(db), HorarioSemana.porDefecto);
    final h = HorarioSemana.porDefecto.conDia(DateTime.saturday, null);
    await configurarHorario(db, h);
    expect(await horarioActual(db), h);
    expect(await configSenaActual(db), ConfigSena.porDefecto);
    await configurarPideSena(db, corte, pide: true);
    expect((await (db.select(db.productos)..where((p) => p.id.equals(corte))).getSingle()).pideSena, isTrue);
  });

  test('los turnos viajan al otro equipo con su cliente, servicio y profesional', () async {
    final otro = baseDeTest();
    addTearDown(otro.close);
    for (final base in [db, otro]) {
      await base.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial' WHERE id = (SELECT MIN(id) FROM usuarios)");
    }
    await anotarTurno(db, cliente: 'Ana', servicioId: corte, profesionalId: usuario, inicio: a(10), usuarioId: usuario);
    for (final tabla in tablasSincronizables.keys) {
      final fallidas = await aplicarCambios(otro, tabla: tabla, filas: await cambiosDesde(db, tabla: tabla, desde: 0));
      expect(fallidas, isEmpty, reason: tabla);
    }
    final delDia = await turnosDelDia(otro, lunes);
    expect(delDia.single.cliente.nombre, 'Ana');
    expect(delDia.single.servicio.nombre, 'Corte');
    expect(delDia.single.profesional?.globalId, 'usuario-inicial');
  });
}
