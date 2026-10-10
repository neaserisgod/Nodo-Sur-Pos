// Turnos de la agenda (`REGLAS-NEGOCIO.md` §21, etapa 4 de `docs/PLAN-SERVICIOS.md`). Las cuentas de horarios están en
// `domain/agenda.dart`.
//
// La seña del turno (columnas `sena_*`) llega con los turnos del bot: es ahí donde se pide. Cobrarla en el celular necesita
// que el cobro aplique una seña, y hoy el celular no cobra ni la de un encargue (se entrega desde la PC).

import 'package:drift/drift.dart';

import '../domain/agenda.dart';
import 'database.dart';
import 'identidad_sync.dart';

/// Un turno con lo que hace falta para mostrarlo.
class TurnoListado {
  const TurnoListado({required this.turno, required this.servicio, required this.profesional, required this.faltas});

  final Turno turno;
  final Producto? servicio;
  final Usuario? profesional;

  /// Cuántas veces el cliente no vino antes (§21: se ve, no bloquea).
  final int faltas;

  EstadoTurno get estado => EstadoTurno.desdeClave(turno.estado);
  DateTime get fin => turno.inicio.add(Duration(minutes: turno.duracionMinutos));
  Ocupado get ocupado => (inicio: turno.inicio, fin: fin);
}

/// La agenda del negocio: horario de atención y cada cuántos minutos se ofrecen turnos.
Future<({HorarioAtencion horario, int intervaloMinutos})> configuracionAgenda(AppDatabase db) async {
  final c = await db.select(db.configuracionNegocioTabla).getSingleOrNull();
  return (horario: HorarioAtencion.desdeJson(c?.horarioAtencion), intervaloMinutos: c?.intervaloTurnosMinutos ?? 15);
}

Future<void> configurarAgenda(AppDatabase db, {HorarioAtencion? horario, int? intervaloMinutos}) {
  if (intervaloMinutos != null && intervaloMinutos <= 0) throw ArgumentError('El intervalo tiene que ser mayor a 0');
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          horarioAtencion: horario == null ? const Value.absent() : Value(horario.aJson()),
          intervaloTurnosMinutos: intervaloMinutos == null ? const Value.absent() : Value(intervaloMinutos),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

DateTime _inicioDelDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Los turnos de [dia] (de [profesionalId] si se pasa), por hora. Incluye los cancelados y los que no vinieron: la agenda los
/// muestra apagados.
Future<List<TurnoListado>> turnosDelDia(AppDatabase db, DateTime dia, {int? profesionalId}) async {
  final desde = _inicioDelDia(dia);
  final q = db.select(db.turnos)
    ..where((t) => t.inicio.isBiggerOrEqualValue(desde) & t.inicio.isSmallerThanValue(desde.add(const Duration(days: 1))))
    ..orderBy([(t) => OrderingTerm.asc(t.inicio)]);
  if (profesionalId != null) q.where((t) => t.profesionalId.equals(profesionalId));
  final turnos = await q.get();
  final servicios = {for (final p in await db.select(db.productos).get()) p.id: p};
  final usuarios = {for (final u in await db.select(db.usuarios).get()) u.id: u};
  final faltas = await _faltasPorTelefono(db);
  return [
    for (final t in turnos)
      TurnoListado(
        turno: t,
        servicio: servicios[t.servicioId],
        profesional: usuarios[t.profesionalId],
        faltas: faltas[_clave(t)] ?? 0,
      ),
  ];
}

/// Un cliente se reconoce por su teléfono; sin teléfono, por el nombre.
String _clave(Turno t) => (t.telefono?.trim().isNotEmpty ?? false) ? t.telefono!.trim() : t.nombreCliente.trim().toLowerCase();

Future<Map<String, int>> _faltasPorTelefono(AppDatabase db) async {
  final noVino = await (db.select(db.turnos)..where((t) => t.estado.equals(EstadoTurno.noVino.clave))).get();
  final faltas = <String, int>{};
  for (final t in noVino) {
    faltas[_clave(t)] = (faltas[_clave(t)] ?? 0) + 1;
  }
  return faltas;
}

/// Lo que ya ocupa la agenda de [profesionalId] (o la única, si es null) el [dia]: para los horarios libres y los sobreturnos.
Future<List<Ocupado>> ocupadosDelDia(AppDatabase db, DateTime dia, {int? profesionalId, int? exceptoTurnoId}) async {
  return [
    for (final t in await turnosDelDia(db, dia, profesionalId: profesionalId))
      if (t.estado.ocupaHorario && t.turno.id != exceptoTurnoId) t.ocupado,
  ];
}

/// Si el turno se pisa con otro del mismo profesional (§21: avisa y deja guardarlo).
Future<bool> esSobreturno(
  AppDatabase db, {
  required DateTime inicio,
  required int duracionMinutos,
  int? profesionalId,
  int? exceptoTurnoId,
}) async {
  final nuevo = (inicio: inicio, fin: inicio.add(Duration(minutes: duracionMinutos)));
  final ocupados = await ocupadosDelDia(db, inicio, profesionalId: profesionalId, exceptoTurnoId: exceptoTurnoId);
  return ocupados.any((o) => seSuperponen(o, nuevo));
}

/// El cliente del turno: el que ya existe con ese teléfono, o uno nuevo (§21: al confirmarse queda guardado). Sin teléfono no
/// se crea: un nombre suelto no alcanza para reconocerlo la próxima vez.
Future<int?> _clienteDe(AppDatabase db, {required String nombre, String? telefono}) async {
  final tel = telefono?.trim();
  if (tel == null || tel.isEmpty) return null;
  final existente = await (db.select(db.clientes)..where((c) => c.telefono.equals(tel))..limit(1)).getSingleOrNull();
  if (existente != null) return existente.id;
  return db.into(db.clientes).insert(
        ClientesCompanion.insert(
          nombre: nombre.trim(),
          telefono: Value(tel),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

/// Anota un turno. Devuelve el id.
Future<int> crearTurno(
  AppDatabase db, {
  required String nombreCliente,
  String? telefono,
  required int servicioId,
  int? profesionalId,
  required DateTime inicio,
  String origen = 'app',
  EstadoTurno estado = EstadoTurno.confirmado,
  String? nota,
  required int usuarioId,
}) {
  if (nombreCliente.trim().isEmpty) throw ArgumentError('Falta el nombre');
  return db.transaction(() async {
    final servicio = await (db.select(db.productos)..where((p) => p.id.equals(servicioId))).getSingle();
    if (!servicio.esServicio) throw ArgumentError('"${servicio.nombre}" no es un servicio');
    return db.into(db.turnos).insert(
          TurnosCompanion.insert(
            clienteId: Value(await _clienteDe(db, nombre: nombreCliente, telefono: telefono)),
            nombreCliente: nombreCliente.trim(),
            telefono: Value(telefono?.trim().isEmpty ?? true ? null : telefono!.trim()),
            servicioId: Value(servicioId),
            duracionMinutos: servicio.duracionMinutos ?? 30,
            profesionalId: Value(profesionalId),
            inicio: inicio,
            estado: Value(estado.clave),
            origen: Value(origen),
            nota: Value(nota),
            usuarioId: usuarioId,
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
  });
}

Future<Turno> _turno(AppDatabase db, int id) => (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();

Future<void> _escribir(AppDatabase db, int id, TurnosCompanion cambios) =>
    (db.update(db.turnos)..where((t) => t.id.equals(id))).write(cambios.copyWith(actualizadoEn: Value(DateTime.now())));

/// Lo cambia de día, hora o profesional.
Future<void> moverTurno(AppDatabase db, int id, {required DateTime inicio, int? profesionalId}) =>
    _escribir(db, id, TurnosCompanion(inicio: Value(inicio), profesionalId: Value(profesionalId)));

/// Llegó o no vino. Cobrar y cancelar tienen lo suyo ([marcarTurnoCobrado], [cancelarTurno]).
Future<void> marcarTurno(AppDatabase db, int id, EstadoTurno estado) {
  if (estado == EstadoTurno.cobrado || estado == EstadoTurno.cancelado) throw ArgumentError('Usá cobrar o cancelar');
  return _escribir(db, id, TurnosCompanion(estado: Value(estado.clave)));
}

/// Cancela el turno: libera el horario.
Future<void> cancelarTurno(AppDatabase db, int id) async {
  if (EstadoTurno.desdeClave((await _turno(db, id)).estado) == EstadoTurno.cobrado) {
    throw ArgumentError('Un turno cobrado no se cancela: se anula la venta.');
  }
  await _escribir(db, id, TurnosCompanion(estado: Value(EstadoTurno.cancelado.clave)));
}

/// El turno queda cobrado con la venta que lo cobró (al cobrarlo desde la agenda).
Future<void> marcarTurnoCobrado(AppDatabase db, int id, {required int ventaId}) =>
    _escribir(db, id, TurnosCompanion(estado: Value(EstadoTurno.cobrado.clave), ventaId: Value(ventaId)));
