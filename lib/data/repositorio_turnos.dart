// La agenda de turnos (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4): anotar, mover, cambiar de estado, tomar
// y devolver la seña, y leer el día. Las cuentas (con quién choca, huecos libres, seña sugerida) viven en
// `domain/turnos.dart`. Todo sobre la base del celular y viaja por la sync.
//
// La seña es la de los encargues (§15): entra a la caja como ingreso al tomarla, vuelve por la misma caja si se devuelve, y
// al cobrar el turno es un pago de la venta que no mueve la caja de nuevo (`registrarVenta`, con `turnoId`).

import 'package:drift/drift.dart';

import '../domain/modulos.dart';
import '../domain/normalizacion_texto.dart';
import '../domain/sena.dart';
import '../domain/turnos.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_encargues.dart' show registrarDevolucionSena;
import 'repositorio_gastos.dart' show MedioGasto;
import 'repositorio_ingresos.dart';

/// El turno choca con otro del mismo profesional (Regla 21: no se deja anotar ni mover ahí).
class TurnoSuperpuesto extends ArgumentError {
  TurnoSuperpuesto(this.con, this.cliente)
      : super('Se pisa con el turno de $cliente a las ${con.inicio.hour}:${con.inicio.minute.toString().padLeft(2, '0')}.');

  final TurnoParaAgenda con;
  final String cliente;
}

Future<HorarioSemana> horarioActual(AppDatabase db) async => HorarioSemana.desdeTexto((await configuracionNegocioActual(db)).horarioAtencion);

Future<ConfigSena> configSenaActual(AppDatabase db) async => ConfigSena.desdeTexto((await configuracionNegocioActual(db)).configSena);

Future<void> configurarHorario(AppDatabase db, HorarioSemana horario) {
  for (final d in horario.dias) {
    d?.validar();
  }
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(horarioAtencion: Value(horario.aTexto()), actualizadoEn: Value(DateTime.now())),
      );
}

Future<void> configurarSena(AppDatabase db, ConfigSena config) {
  if (config.valor < 0) throw ArgumentError('La seña no puede ser negativa');
  if (config.esPorcentaje && config.valor > 10000) throw ArgumentError('La seña no puede ser más del 100 %');
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(configSena: Value(config.aTexto()), actualizadoEn: Value(DateTime.now())),
      );
}

/// Si un servicio pide seña (cuando el negocio la pide en "algunos servicios").
Future<void> configurarPideSena(AppDatabase db, int servicioId, {required bool pide}) {
  return (db.update(db.productos)..where((p) => p.id.equals(servicioId))).write(
    ProductosCompanion(pideSena: Value(pide), actualizadoEn: Value(DateTime.now())),
  );
}

/// El cliente con ese nombre (sin importar mayúsculas ni acentos) y, si se da, ese teléfono; si no hay, uno nuevo. Así el
/// mismo cliente anotado dos veces no queda repetido.
Future<int> clienteParaTurno(AppDatabase db, {required String nombre, String? telefono}) async {
  final limpio = nombre.trim();
  if (limpio.isEmpty) throw ArgumentError('Falta el nombre del cliente');
  final tel = telefono?.trim().isEmpty ?? true ? null : telefono!.trim();
  final normal = normalizarTexto(limpio);
  for (final c in await (db.select(db.clientes)..where((c) => c.activo.equals(true))).get()) {
    if (normalizarTexto(c.nombre) == normal && (tel == null || c.telefono == null || c.telefono == tel)) {
      if (tel != null && c.telefono == null) {
        await (db.update(db.clientes)..where((x) => x.id.equals(c.id))).write(
          ClientesCompanion(telefono: Value(tel), actualizadoEn: Value(DateTime.now())),
        );
      }
      return c.id;
    }
  }
  return db.into(db.clientes).insert(
        ClientesCompanion.insert(
          nombre: limpio,
          telefono: Value(tel),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

TurnoParaAgenda _paraAgenda(FilaTurno t) => TurnoParaAgenda(
      id: t.id,
      profesionalId: t.profesionalId,
      inicio: t.inicio,
      duracionMinutos: t.duracionMinutos,
      estado: EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado,
    );

Future<List<FilaTurno>> _delDia(AppDatabase db, DateTime dia) {
  final desde = DateTime(dia.year, dia.month, dia.day);
  return (db.select(db.turnos)
        ..where((t) => t.inicio.isBiggerOrEqualValue(desde) & t.inicio.isSmallerThanValue(desde.add(const Duration(days: 1)))))
      .get();
}

/// Que no choque con otro del mismo profesional ese día (Regla 21).
Future<void> _exigirLibre(AppDatabase db, {required DateTime inicio, required int duracionMinutos, required int? profesionalId, int? excepto}) async {
  final del = await _delDia(db, inicio);
  final varios = (await modulosNegocioActuales(db)).estaActivo(Modulo.profesionales);
  final choca = conQuienChoca(
    inicio: inicio,
    duracionMinutos: duracionMinutos,
    profesionalId: profesionalId,
    otros: [for (final t in del) _paraAgenda(t)],
    variosProfesionales: varios,
    excepto: excepto,
  );
  if (choca == null) return;
  final fila = del.firstWhere((t) => t.id == choca.id);
  final cliente = await (db.select(db.clientes)..where((c) => c.id.equals(fila.clienteId))).getSingle();
  throw TurnoSuperpuesto(choca, cliente.nombre);
}

Future<void> _tomarSena(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  required bool esEfectivo,
  required String cliente,
}) =>
    registrarIngresoRapido(
      db,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: montoCentavos,
      medio: cajaDeLaSena(esEfectivo: esEfectivo) == CajaDeSena.cajon ? MedioGasto.cajonNormal : MedioGasto.mercadoPago,
      motivo: 'Seña turno de $cliente',
    );

/// Anota un turno. Uno de la app nace confirmado; uno de WhatsApp, sin confirmar. Con [senaCentavos] se toma la seña en el
/// momento (hace falta [sesionCajaId], la caja abierta). Devuelve el id.
Future<int> anotarTurno(
  AppDatabase db, {
  required String cliente,
  String? telefono,
  required int servicioId,
  int? profesionalId,
  required DateTime inicio,
  OrigenTurno origen = OrigenTurno.app,
  String? nota,
  int senaCentavos = 0,
  bool senaEsEfectivo = true,
  int? sesionCajaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final servicio = await (db.select(db.productos)..where((p) => p.id.equals(servicioId))).getSingle();
    if (!servicio.esServicio) throw ArgumentError('"${servicio.nombre}" no es un servicio');
    if (senaCentavos < 0) throw ArgumentError('La seña no puede ser negativa');
    if (senaCentavos > 0 && sesionCajaId == null) throw ArgumentError('Para tomar una seña hace falta la caja abierta.');
    final duracion = servicio.duracionMinutos ?? 30;
    await _exigirLibre(db, inicio: inicio, duracionMinutos: duracion, profesionalId: profesionalId);
    final clienteId = await clienteParaTurno(db, nombre: cliente, telefono: telefono);
    final id = await db.into(db.turnos).insert(
          TurnosCompanion.insert(
            clienteId: clienteId,
            servicioId: servicioId,
            profesionalId: Value(profesionalId),
            inicio: inicio,
            duracionMinutos: duracion,
            estado: Value((origen == OrigenTurno.app ? EstadoTurno.confirmado : EstadoTurno.sinConfirmar).clave),
            origen: Value(origen.clave),
            senaCentavos: Value(senaCentavos),
            senaEsEfectivo: Value(senaEsEfectivo),
            nota: Value(nota?.trim().isEmpty ?? true ? null : nota!.trim()),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
    if (senaCentavos > 0) {
      await _tomarSena(db, sesionCajaId: sesionCajaId!, usuarioId: usuarioId, montoCentavos: senaCentavos, esEfectivo: senaEsEfectivo, cliente: cliente.trim());
    }
    return id;
  });
}

Future<FilaTurno> _turno(AppDatabase db, int id) => (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();

Future<String> _nombreCliente(AppDatabase db, int clienteId) async =>
    (await (db.select(db.clientes)..where((c) => c.id.equals(clienteId))).getSingle()).nombre;

/// Toma (o suma) seña a un turno que todavía no terminó. Una sola caja por turno: la de la primera seña.
Future<void> tomarSenaDeTurno(
  AppDatabase db, {
  required int turnoId,
  required int montoCentavos,
  required bool esEfectivo,
  required int sesionCajaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    if (montoCentavos <= 0) throw ArgumentError('La seña tiene que ser mayor a 0');
    final t = await _turno(db, turnoId);
    if ((EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado).terminado) throw ArgumentError('Ese turno ya terminó');
    if (t.senaCentavos > 0 && t.senaEsEfectivo != esEfectivo) {
      throw ArgumentError('La seña de este turno entró por ${t.senaEsEfectivo ? 'efectivo' : 'Mercado Pago'}: sumala por el mismo medio.');
    }
    await (db.update(db.turnos)..where((x) => x.id.equals(turnoId))).write(
      TurnosCompanion(senaCentavos: Value(t.senaCentavos + montoCentavos), senaEsEfectivo: Value(esEfectivo), actualizadoEn: Value(DateTime.now())),
    );
    await _tomarSena(db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, montoCentavos: montoCentavos, esEfectivo: esEfectivo, cliente: await _nombreCliente(db, t.clienteId));
  });
}

/// Cambia el día, la hora o el profesional de un turno que no terminó, sin pisar otro.
Future<void> moverTurno(AppDatabase db, {required int turnoId, required DateTime inicio, int? profesionalId}) {
  return db.transaction(() async {
    final t = await _turno(db, turnoId);
    if ((EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado).terminado) throw ArgumentError('Ese turno ya terminó');
    await _exigirLibre(db, inicio: inicio, duracionMinutos: t.duracionMinutos, profesionalId: profesionalId, excepto: turnoId);
    await (db.update(db.turnos)..where((x) => x.id.equals(turnoId))).write(
      TurnosCompanion(inicio: Value(inicio), profesionalId: Value(profesionalId), actualizadoEn: Value(DateTime.now())),
    );
  });
}

/// Confirmar, "llegó", "no vino" o cancelar (cobrar es [registrarVenta] con el turno). Al cancelar, la seña se devuelve; si
/// no vino, según la configuración (Regla 21). Devolver necesita la caja abierta ([sesionCajaId]). Devuelve lo devuelto.
Future<int> cambiarEstadoTurno(
  AppDatabase db, {
  required int turnoId,
  required EstadoTurno estado,
  required int usuarioId,
  int? sesionCajaId,
}) {
  return db.transaction(() async {
    if (estado == EstadoTurno.cobrado) throw ArgumentError('Un turno se cobra desde Vender');
    final t = await _turno(db, turnoId);
    final actual = EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado;
    if (!puedePasar(actual, estado)) throw ArgumentError('Un turno "${actual.nombre}" no puede pasar a "${estado.nombre}"');
    final devolver = senaADevolver(senaCentavos: t.senaCentavos, estadoFinal: estado, siNoViene: (await configSenaActual(db)).siNoViene);
    if (devolver > 0) {
      if (sesionCajaId == null) throw ArgumentError('Para devolver la seña hace falta la caja abierta.');
      await registrarDevolucionSena(
        db,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        montoCentavos: devolver,
        esEfectivo: t.senaEsEfectivo,
        motivo: 'Devolución de seña, turno de ${await _nombreCliente(db, t.clienteId)}',
      );
    }
    await (db.update(db.turnos)..where((x) => x.id.equals(turnoId))).write(
      TurnosCompanion(estado: Value(estado.clave), actualizadoEn: Value(DateTime.now())),
    );
    return devolver;
  });
}

/// La seña de un turno que todavía se puede cobrar (la usa `registrarVenta`, como `senaPendienteDe` de un encargue).
Future<({int centavos, bool esEfectivo})> senaPendienteDeTurno(AppDatabase db, int turnoId) async {
  final t = await (db.select(db.turnos)..where((x) => x.id.equals(turnoId))).getSingleOrNull();
  if (t == null || (EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado).terminado) return (centavos: 0, esEfectivo: true);
  return (centavos: t.senaCentavos, esEfectivo: t.senaEsEfectivo);
}

/// Lo llama `registrarVenta` dentro de su transacción: el turno queda cobrado con su venta.
Future<void> marcarTurnoCobrado(AppDatabase db, int turnoId, {required int ventaId}) async {
  final t = await _turno(db, turnoId);
  final actual = EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado;
  if (!puedePasar(actual, EstadoTurno.cobrado)) throw ArgumentError('Ese turno ya está ${actual.nombre.toLowerCase()}');
  await (db.update(db.turnos)..where((x) => x.id.equals(turnoId))).write(
    TurnosCompanion(estado: Value(EstadoTurno.cobrado.clave), ventaId: Value(ventaId), actualizadoEn: Value(DateTime.now())),
  );
}

/// Un turno con lo que muestra la agenda.
class TurnoDeAgenda {
  const TurnoDeAgenda({required this.turno, required this.cliente, required this.servicio, required this.profesional});

  final FilaTurno turno;
  final Cliente cliente;
  final Producto servicio;
  final Usuario? profesional;

  EstadoTurno get estado => EstadoTurno.desdeClave(turno.estado) ?? EstadoTurno.confirmado;
  OrigenTurno get origen => OrigenTurno.desdeClave(turno.origen);
  TurnoParaAgenda get paraAgenda => _paraAgenda(turno);
}

/// Los turnos de [dia], por hora.
Future<List<TurnoDeAgenda>> turnosDelDia(AppDatabase db, DateTime dia) async {
  final filas = await _delDia(db, dia);
  if (filas.isEmpty) return const [];
  final clientes = {for (final c in await (db.select(db.clientes)..where((c) => c.id.isIn(filas.map((t) => t.clienteId)))).get()) c.id: c};
  final servicios = {for (final p in await (db.select(db.productos)..where((p) => p.id.isIn(filas.map((t) => t.servicioId)))).get()) p.id: p};
  final usuarios = {for (final u in await db.select(db.usuarios).get()) u.id: u};
  return [
    for (final t in filas..sort((a, b) => a.inicio.compareTo(b.inicio)))
      if (clientes[t.clienteId] case final c?)
        if (servicios[t.servicioId] case final s?)
          TurnoDeAgenda(turno: t, cliente: c, servicio: s, profesional: t.profesionalId == null ? null : usuarios[t.profesionalId]),
  ];
}

/// Cuántos turnos que ocupan horario hay por día entre [desde] y [hasta] (los puntos de la tira de días).
Future<Map<DateTime, int>> turnosPorDia(AppDatabase db, DateTime desde, DateTime hasta) async {
  final filas = await (db.select(db.turnos)..where((t) => t.inicio.isBiggerOrEqualValue(desde) & t.inicio.isSmallerThanValue(hasta))).get();
  final cuenta = <DateTime, int>{};
  for (final t in filas) {
    if (!(EstadoTurno.desdeClave(t.estado) ?? EstadoTurno.confirmado).ocupaHorario) continue;
    final dia = DateTime(t.inicio.year, t.inicio.month, t.inicio.day);
    cuenta[dia] = (cuenta[dia] ?? 0) + 1;
  }
  return cuenta;
}
