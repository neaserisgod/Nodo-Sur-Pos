// La Agenda contra una base real (`REGLAS-NEGOCIO.md` §21): dar, mover, cancelar, "no vino", la seña (entra a la caja como
// ingreso y se descuenta al cobrar) y que el cobro deje el turno atendido.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/turnos.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int semi;
  late int retiro;

  // Lunes 12 de octubre de 2026: con el horario de arranque, de 9 a 20.
  final lunes = DateTime(2026, 10, 12);
  DateTime a(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Caro'));
    semi = await crearServicio(db, nombre: 'Semipermanente', precioCentavos: 1800000, duracionMinutos: 60, pideSena: true, usuarioId: usuarioId);
    retiro = await crearServicio(db, nombre: 'Retiro', precioCentavos: 600000, duracionMinutos: 30, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  Future<Turno> turno(int id) => (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();

  Future<List<MovimientoCaja>> movimientos(int sesion) =>
      (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesion))).get();

  test('dar un turno guarda la foto del servicio, la seña que pide y a la persona como cliente', () async {
    final id = await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: ' Ana ', telefono: '5492944111111', usuarioId: usuarioId);
    final t = await turno(id);
    expect(t.servicioNombre, 'Semipermanente');
    expect(t.duracionMinutos, 60);
    expect(t.senaPedidaCentavos, 540000); // 30 % de $18.000
    expect(t.estado, 'CONFIRMADO');
    expect(t.nombreCliente, 'Ana');
    expect(t.globalId, isNotNull);
    final cliente = await (db.select(db.clientes)..where((c) => c.id.equals(t.clienteId!))).getSingle();
    expect(cliente.telefono, '5492944111111');

    // El mismo teléfono otra vez es la misma clienta.
    final otro = await crearTurno(db, servicioId: retiro, inicio: a(15), nombreCliente: 'Anita', telefono: '5492944111111', usuarioId: usuarioId);
    expect((await turno(otro)).clienteId, t.clienteId);
  });

  test('los horarios libres no ofrecen lo ocupado; un cancelado libera su lugar', () async {
    final id = await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', usuarioId: usuarioId);
    var libres = await horariosLibresDelDia(db, lunes, duracionMin: 60);
    expect(libres, isNot(contains(a(10))));
    expect(libres, isNot(contains(a(9, 30))));
    expect(libres, contains(a(9)));
    expect(libres, contains(a(11)));
    expect(await turnosQueSePisan(db, (inicio: a(10, 30), duracionMin: 30)), hasLength(1));

    await cancelarTurno(db, id, usuarioId: usuarioId);
    libres = await horariosLibresDelDia(db, lunes, duracionMin: 60);
    expect(libres, contains(a(10)));
  });

  test('el sobreturno se guarda igual (la app avisa y deja)', () async {
    await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', usuarioId: usuarioId);
    await crearTurno(db, servicioId: retiro, inicio: a(10, 15), nombreCliente: 'Bea', usuarioId: usuarioId);
    expect(await turnosDelDia(db, lunes), hasLength(2));
  });

  test('cada profesional tiene su agenda', () async {
    final otra = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Lu'));
    await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', profesionalId: usuarioId, usuarioId: usuarioId);
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 60, profesionalId: otra), contains(a(10)));
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 60, profesionalId: usuarioId), isNot(contains(a(10))));
    expect(await turnosDelDia(db, lunes, profesionalId: otra), isEmpty);
  });

  test('la seña al dar el turno entra a la caja como ingreso, y al cobrar se descuenta sin volver a moverla', () async {
    final sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final id = await crearTurno(
      db,
      servicioId: semi,
      inicio: a(10),
      nombreCliente: 'Ana',
      usuarioId: usuarioId,
      senaCentavos: 540000,
      senaEsEfectivo: true,
      sesionCajaId: sesion,
    );
    var movs = await movimientos(sesion);
    expect(movs.where((m) => m.tipo == 'INGRESO').single.montoCentavos, 540000);

    final cuenta = await cuentaDeTurno(db, id);
    expect(cuenta.aplicadaCentavos, 540000);
    expect(cuenta.aCobrarCentavos, 1260000);

    final r = await registrarVentaSegunMedio(
      db,
      lineas: [await lineaDeTurno(db, id)],
      medio: ComposicionPago.efectivo,
      sesionCajaId: sesion,
      usuarioId: usuarioId,
      turnoId: id,
    );
    expect(r.totalCentavos, 1800000);
    final t = await turno(id);
    expect(t.estado, EstadoTurno.atendido.clave);
    expect(t.ventaId, r.ventaId);
    movs = await movimientos(sesion);
    // El cajón recibe la seña y el resto: en total, el precio del servicio una sola vez.
    expect(movs.fold<int>(0, (s, m) => s + m.montoCentavos), 1800000);
    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(r.ventaId))).get();
    expect(pagos.map((p) => p.montoCentavos).fold<int>(0, (s, m) => s + m), 1800000);
    expect(pagos.where((p) => p.canal == 'sena').single.montoCentavos, 540000);

    // Cobrarlo de nuevo no se puede.
    await expectLater(
      registrarVentaSegunMedio(db, lineas: [await lineaDeTurno(db, id)], medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuarioId, turnoId: id),
      throwsArgumentError,
    );
  });

  test('una seña sin caja abierta queda anotada y entra al abrir la próxima caja', () async {
    final id = await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', usuarioId: usuarioId);
    await registrarSenaDeTurno(db, id, montoCentavos: 540000, esEfectivo: false, usuarioId: usuarioId);
    expect((await turno(id)).senaEnCaja, isFalse);

    final sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    expect(await ingresarSenasPendientes(db, sesionCajaId: sesion, usuarioId: usuarioId), 1);
    expect((await turno(id)).senaEnCaja, isTrue);
    final ingreso = (await movimientos(sesion)).single;
    expect(ingreso.tipo, 'INGRESO');
    expect(ingreso.medioPagoId, isNotNull); // entró por Mercado Pago
    // Abrir otra vez no la vuelve a contar.
    expect(await ingresarSenasPendientes(db, sesionCajaId: sesion, usuarioId: usuarioId), 0);
  });

  test('cancelar: por defecto la seña se pierde; configurado, se devuelve por la misma caja', () async {
    final sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final uno = await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', usuarioId: usuarioId, senaCentavos: 540000, sesionCajaId: sesion);
    expect(await cancelarTurno(db, uno, usuarioId: usuarioId, sesionCajaId: sesion), 0);
    expect((await movimientos(sesion)).where((m) => m.tipo == 'DEVOLUCION_SENA'), isEmpty);

    await guardarConfigAgenda(db, const ConfigAgenda(sena: ConfigSena(devolverAlCancelar: true)));
    final dos = await crearTurno(db, servicioId: semi, inicio: a(12), nombreCliente: 'Bea', usuarioId: usuarioId, senaCentavos: 540000, sesionCajaId: sesion);
    await expectLater(cancelarTurno(db, dos, usuarioId: usuarioId), throwsArgumentError); // sin caja no se puede devolver
    expect(await cancelarTurno(db, dos, usuarioId: usuarioId, sesionCajaId: sesion), 540000);
    expect((await movimientos(sesion)).where((m) => m.tipo == 'DEVOLUCION_SENA').single.montoCentavos, 540000);
    expect((await turno(dos)).estado, 'CANCELADO');
  });

  test('no vino: libera el horario y la persona lleva la cuenta', () async {
    final id = await crearTurno(db, servicioId: retiro, inicio: a(10), nombreCliente: 'Ana', telefono: '5492944111111', usuarioId: usuarioId);
    await marcarNoVino(db, id);
    final otro = await crearTurno(db, servicioId: retiro, inicio: a(11), nombreCliente: 'Ana', telefono: '5492944111111', usuarioId: usuarioId);
    final dia = await turnosDelDia(db, lunes);
    expect(dia.firstWhere((t) => t.turno.id == otro).faltas, 1);
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 30), contains(a(10)));
  });

  test('un turno del bot que espera seña no guarda cliente hasta pagar, y vence solo', () async {
    final id = await crearTurno(
      db,
      servicioId: semi,
      inicio: a(10),
      nombreCliente: 'Caro',
      telefono: '5492944222222',
      usuarioId: usuarioId,
      estado: EstadoTurno.esperandoSena,
      senaVence: a(9),
      origen: 'BOT',
      idRemoto: 't-1',
    );
    expect((await turno(id)).clienteId, isNull);
    // Bajarlo otra vez no lo duplica.
    expect(await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Caro', usuarioId: usuarioId, idRemoto: 't-1'), id);
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 60), isNot(contains(a(10))));

    expect(await liberarSenasVencidas(db, ahora: a(9, 30)), 1);
    expect((await turno(id)).estado, 'CANCELADO');
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 60), contains(a(10)));
  });

  test('mover un turno', () async {
    final id = await crearTurno(db, servicioId: semi, inicio: a(10), nombreCliente: 'Ana', usuarioId: usuarioId);
    await moverTurno(db, id, a(16));
    expect((await turno(id)).inicio, a(16));
    expect(await horariosLibresDelDia(db, lunes, duracionMin: 60, salvoTurnoId: id), contains(a(16)));
  });

  test('la configuración de la agenda va y vuelve', () async {
    const horario = HorarioAtencion({1: (desdeMin: 600, hastaMin: 1080), 2: null, 3: null, 4: null, 5: null, 6: null, 7: null});
    await guardarConfigAgenda(
      db,
      const ConfigAgenda(horario: horario, pasoMinutos: 30, sena: ConfigSena(modo: ModoSena.todos, porcentaje: 50), aliasSena: ' caro.unas '),
    );
    final c = await configAgendaActual(db);
    expect(c.horario.toJson(), horario.toJson());
    expect(c.pasoMinutos, 30);
    expect(c.sena.modo, ModoSena.todos);
    expect(c.aliasSena, 'caro.unas');
    final libres = await horariosLibresDelDia(db, lunes, duracionMin: 60);
    expect(libres.first, a(10));
    expect(libres.map((d) => d.minute).toSet(), {0, 30});
  });
}
