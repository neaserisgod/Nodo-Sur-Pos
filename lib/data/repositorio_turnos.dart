// La Agenda (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4): dar, mover, cancelar y cobrar turnos. Las cuentas
// (qué horario está libre, cuánto es la seña) viven en `domain/turnos.dart`; acá solo se leen y se guardan.
//
// La seña de un turno es la de los encargues (`domain/sena.dart`, Regla 15): entra a la caja como INGRESO (no es venta) y al
// cobrar el turno se descuenta como un pago que no vuelve a mover la caja (`registrarVenta(turnoId:)`). Si se cancela, se
// pierde o se devuelve según la configuración del negocio.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/sena.dart';
import '../domain/turnos.dart';
import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_encargues.dart' show registrarDevolucionSena;
import 'repositorio_gastos.dart' show MedioGasto;
import 'repositorio_ingresos.dart';
import 'repositorio_ventas.dart' show lineaDesdeProducto, sesionAbierta;

/// Cómo trabaja la Agenda de este negocio: horario de atención, cada cuánto se ofrecen turnos y la seña.
class ConfigAgenda {
  const ConfigAgenda({
    this.horario = HorarioAtencion.porDefecto,
    this.pasoMinutos = 15,
    this.sena = const ConfigSena(),
    this.aliasSena = '',
    this.titularSena = '',
  });

  final HorarioAtencion horario;
  final int pasoMinutos;
  final ConfigSena sena;
  final String aliasSena;
  final String titularSena;
}

ConfigAgenda configAgendaDe(ConfiguracionNegocio c) => ConfigAgenda(
      horario: c.horarioAtencion == null ? HorarioAtencion.porDefecto : HorarioAtencion.desdeJson(_jsonOVacio(c.horarioAtencion!)),
      pasoMinutos: c.pasoTurnosMinutos > 0 ? c.pasoTurnosMinutos : 15,
      sena: ConfigSena(
        modo: ModoSena.desdeClave(c.senaModo),
        porcentaje: c.senaPorcentaje,
        montoFijoCentavos: c.senaMontoFijoCentavos,
        devolverAlCancelar: c.senaDevolverAlCancelar,
      ),
      aliasSena: c.aliasSena,
      titularSena: c.titularSena,
    );

Object? _jsonOVacio(String texto) {
  try {
    return jsonDecode(texto);
  } catch (_) {
    return null;
  }
}

Future<ConfigAgenda> configAgendaActual(AppDatabase db) async => configAgendaDe(await configuracionNegocioActual(db));

/// Guarda la configuración de la Agenda. Viaja con la fila de configuración por la sync, y de ahí la toma el bot.
Future<void> guardarConfigAgenda(AppDatabase db, ConfigAgenda c) {
  if (c.pasoMinutos <= 0) throw ArgumentError('Cada cuánto se ofrecen turnos tiene que ser más de 0 minutos');
  if (c.sena.porcentaje < 0 || c.sena.porcentaje > 100) throw ArgumentError('El porcentaje de la seña va de 0 a 100');
  return db.update(db.configuracionNegocioTabla).write(ConfiguracionNegocioTablaCompanion(
        horarioAtencion: Value(jsonEncode(c.horario.toJson())),
        pasoTurnosMinutos: Value(c.pasoMinutos),
        senaModo: Value(c.sena.modo.clave),
        senaPorcentaje: Value(c.sena.porcentaje),
        senaMontoFijoCentavos: Value(c.sena.montoFijoCentavos),
        senaDevolverAlCancelar: Value(c.sena.devolverAlCancelar),
        aliasSena: Value(c.aliasSena.trim()),
        titularSena: Value(c.titularSena.trim()),
        actualizadoEn: Value(DateTime.now()),
      ));
}

/// Un turno listo para mostrar.
class TurnoAgenda {
  const TurnoAgenda({required this.turno, this.profesional, this.faltas = 0});
  final Turno turno;

  /// Nombre de quien atiende, si hay.
  final String? profesional;

  /// Cuántas veces no vino esta persona (por cliente guardado).
  final int faltas;

  EstadoTurno get estado => EstadoTurno.desdeClave(turno.estado);
  DateTime get inicio => turno.inicio;
  DateTime get fin => turno.inicio.add(Duration(minutes: turno.duracionMinutos));
  TramoOcupado get tramo => (inicio: turno.inicio, duracionMin: turno.duracionMinutos);
}

/// Los turnos que empiezan entre [desde] (incluido) y [hasta] (excluido), por hora. Con [profesionalId], solo los suyos (un
/// empleado ve su agenda, §21). Con [incluirLiberados] en false, sin los cancelados.
Future<List<TurnoAgenda>> turnosEntre(
  AppDatabase db, {
  required DateTime desde,
  required DateTime hasta,
  int? profesionalId,
  bool incluirLiberados = true,
}) async {
  final q = db.select(db.turnos)
    ..where((t) => t.inicio.isBiggerOrEqualValue(desde) & t.inicio.isSmallerThanValue(hasta))
    ..orderBy([(t) => OrderingTerm.asc(t.inicio)]);
  if (profesionalId != null) q.where((t) => t.profesionalId.equals(profesionalId));
  if (!incluirLiberados) q.where((t) => t.estado.equals(EstadoTurno.cancelado.clave).not());
  final filas = await q.get();
  final usuarios = {for (final u in await db.select(db.usuarios).get()) u.id: u.nombre};
  final faltas = await _faltasPorCliente(db, {for (final t in filas) if (t.clienteId != null) t.clienteId!});
  return [
    for (final t in filas)
      TurnoAgenda(
        turno: t,
        profesional: t.profesionalId == null ? null : usuarios[t.profesionalId],
        faltas: t.clienteId == null ? 0 : faltas[t.clienteId] ?? 0,
      ),
  ];
}

/// Los turnos del día de [dia].
Future<List<TurnoAgenda>> turnosDelDia(AppDatabase db, DateTime dia, {int? profesionalId}) {
  final desde = DateTime(dia.year, dia.month, dia.day);
  return turnosEntre(db, desde: desde, hasta: DateTime(dia.year, dia.month, dia.day + 1), profesionalId: profesionalId);
}

Future<Map<int, int>> _faltasPorCliente(AppDatabase db, Set<int> clientes) async {
  if (clientes.isEmpty) return const {};
  final filas = await (db.select(db.turnos)
        ..where((t) => t.clienteId.isIn(clientes) & t.estado.equals(EstadoTurno.noVino.clave)))
      .get();
  final r = <int, int>{};
  for (final t in filas) {
    r[t.clienteId!] = (r[t.clienteId!] ?? 0) + 1;
  }
  return r;
}

/// Lo que ocupa la agenda ese día: los turnos que ocupan su horario, de [profesionalId] (o de todos si es null, el negocio de
/// una sola persona), sin [salvoTurnoId] (el que se está moviendo).
Future<List<TramoOcupado>> ocupadosDelDia(AppDatabase db, DateTime dia, {int? profesionalId, int? salvoTurnoId}) async {
  final turnos = await turnosDelDia(db, dia, profesionalId: profesionalId);
  return [
    for (final t in turnos)
      if (t.estado.ocupa && t.turno.id != salvoTurnoId) t.tramo,
  ];
}

/// Los horarios en que se puede dar un turno de [duracionMin] ese día. Lo que la Agenda ofrece primero; dar otro a mano es un
/// sobreturno (avisa y deja, §21).
Future<List<DateTime>> horariosLibresDelDia(
  AppDatabase db,
  DateTime dia, {
  required int duracionMin,
  int? profesionalId,
  int? salvoTurnoId,
  DateTime? ahora,
}) async {
  final config = await configAgendaActual(db);
  return horariosLibres(
    dia: dia,
    horario: config.horario,
    duracionMin: duracionMin,
    ocupados: await ocupadosDelDia(db, dia, profesionalId: profesionalId, salvoTurnoId: salvoTurnoId),
    pasoMin: config.pasoMinutos,
    ahora: ahora,
  );
}

/// Los turnos que se pisan con [tramo] (para avisar del sobreturno antes de guardar).
Future<List<TurnoAgenda>> turnosQueSePisan(AppDatabase db, TramoOcupado tramo, {int? profesionalId, int? salvoTurnoId}) async {
  final turnos = await turnosDelDia(db, tramo.inicio, profesionalId: profesionalId);
  return [
    for (final t in turnos)
      if (t.estado.ocupa && t.turno.id != salvoTurnoId && seSolapan(t.tramo, tramo)) t,
  ];
}

/// La seña que pide hoy el servicio [servicio], según la configuración del negocio.
Future<int> senaParaServicio(AppDatabase db, Producto servicio) async {
  final config = await configAgendaActual(db);
  return senaDeServicio(precioCentavos: servicio.precioCentavos ?? 0, pideSena: servicio.pideSena, config: config.sena);
}

/// El cliente con ese teléfono o, sin teléfono, con ese nombre exacto; si no existe, se crea (§21: al confirmarse un turno la
/// persona queda guardada como cliente).
Future<int> _clienteDe(AppDatabase db, {required String nombre, String? telefono}) async {
  final tel = telefono?.trim();
  if (tel != null && tel.isNotEmpty) {
    final porTel = await (db.select(db.clientes)..where((c) => c.telefono.equals(tel))..limit(1)).getSingleOrNull();
    if (porTel != null) return porTel.id;
  } else {
    final porNombre = await (db.select(db.clientes)
          ..where((c) => c.nombre.equals(nombre) & c.telefono.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (porNombre != null) return porNombre.id;
  }
  return db.into(db.clientes).insert(ClientesCompanion.insert(
        nombre: nombre,
        telefono: Value(tel == null || tel.isEmpty ? null : tel),
        globalId: Value(generarGlobalId()),
        origenDispositivo: Value(idDispositivoActual),
        actualizadoEn: Value(DateTime.now()),
      ));
}

/// Da un turno. Lo que pise a otro se guarda igual (sobreturno: la pantalla avisa antes con [turnosQueSePisan]).
///
/// Con [senaCentavos] > 0 la persona deja la seña en el momento: entra a la caja de [sesionCajaId] en la MISMA transacción (si no
/// hay caja abierta, queda anotada y entra en la próxima que se abra en este equipo, §21). [senaPedidaCentavos] es la que
/// pide el servicio; sin seña pagada y con seña pedida, un turno del bot queda "esperando seña" (§21).
Future<int> crearTurno(
  AppDatabase db, {
  required int servicioId,
  required DateTime inicio,
  required String nombreCliente,
  String? telefono,
  int? profesionalId,
  required int usuarioId,
  int? duracionMinutos,
  String? nota,
  int senaCentavos = 0,
  bool senaEsEfectivo = true,
  int? sesionCajaId,
  int? senaPedidaCentavos,
  EstadoTurno estado = EstadoTurno.confirmado,
  DateTime? senaVence,
  String origen = 'APP',
  String? idRemoto,
}) {
  final nombre = nombreCliente.trim();
  if (nombre.isEmpty) throw ArgumentError('El turno necesita el nombre de quien viene.');
  if (senaCentavos < 0) throw ArgumentError('La seña no puede ser negativa');
  return db.transaction(() async {
    if (idRemoto != null) {
      final ya = await (db.select(db.turnos)..where((t) => t.idRemoto.equals(idRemoto))).getSingleOrNull();
      if (ya != null) return ya.id; // el mismo turno del bot que vuelve a bajar
    }
    final servicio = await (db.select(db.productos)..where((p) => p.id.equals(servicioId))).getSingle();
    final duracion = duracionMinutos ?? servicio.duracionMinutos ?? 0;
    if (duracion <= 0) throw ArgumentError('El servicio ${servicio.nombre} no tiene duración: cargala en Servicios.');
    final pedida = senaPedidaCentavos ?? await senaParaServicio(db, servicio);
    if (senaCentavos > (servicio.precioCentavos ?? 0) && (servicio.precioCentavos ?? 0) > 0) {
      throw ArgumentError('La seña no puede ser más que lo que vale el servicio');
    }
    final confirmado = estado != EstadoTurno.esperandoSena || senaCentavos > 0;
    final estadoFinal = estado == EstadoTurno.esperandoSena && senaCentavos > 0 ? EstadoTurno.confirmado : estado;
    final clienteId = confirmado ? await _clienteDe(db, nombre: nombre, telefono: telefono) : null;
    final entraYa = senaCentavos > 0 && sesionCajaId != null;
    final id = await db.into(db.turnos).insert(TurnosCompanion.insert(
          servicioId: Value(servicio.id),
          servicioNombre: servicio.nombre,
          duracionMinutos: duracion,
          inicio: inicio,
          clienteId: Value(clienteId),
          nombreCliente: nombre,
          telefono: Value(telefono?.trim().isEmpty ?? true ? null : telefono!.trim()),
          profesionalId: Value(profesionalId),
          estado: Value(estadoFinal.clave),
          senaPedidaCentavos: Value(pedida),
          senaCentavos: Value(senaCentavos),
          senaEsEfectivo: Value(senaEsEfectivo),
          senaEnCaja: Value(senaCentavos == 0 || entraYa),
          senaVence: Value(senaVence),
          origen: Value(origen),
          idRemoto: Value(idRemoto),
          nota: Value(nota?.trim().isEmpty ?? true ? null : nota!.trim()),
          usuarioId: usuarioId,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ));
    if (entraYa) {
      await _ingresarSena(db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, monto: senaCentavos, esEfectivo: senaEsEfectivo, nombre: nombre);
    }
    return id;
  });
}

Future<void> _ingresarSena(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required int monto,
  required bool esEfectivo,
  required String nombre,
}) =>
    registrarIngresoRapido(
      db,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: monto,
      medio: cajaDeLaSena(esEfectivo: esEfectivo) == CajaDeSena.cajon ? MedioGasto.cajonNormal : MedioGasto.mercadoPago,
      motivo: 'Seña turno de $nombre',
    );

Future<Turno> _turno(AppDatabase db, int id) => (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle();

Future<void> _escribir(AppDatabase db, int id, TurnosCompanion cambios) =>
    (db.update(db.turnos)..where((t) => t.id.equals(id))).write(cambios.copyWith(actualizadoEn: Value(DateTime.now())));

/// Anota la seña que pagó la persona. Si el turno esperaba la seña, queda confirmado (y la persona, guardada como cliente).
/// Con [sesionCajaId] entra a la caja ya; sin caja abierta queda anotada y entra en la próxima que se abra en este equipo.
Future<void> registrarSenaDeTurno(
  AppDatabase db,
  int id, {
  required int montoCentavos,
  required bool esEfectivo,
  required int usuarioId,
  int? sesionCajaId,
}) {
  if (montoCentavos <= 0) throw ArgumentError('La seña tiene que ser mayor a cero');
  return db.transaction(() async {
    final t = await _turno(db, id);
    if (!EstadoTurno.desdeClave(t.estado).abierto) throw ArgumentError('Este turno ya no está pendiente.');
    if (t.senaCentavos > 0) throw ArgumentError('Este turno ya tiene la seña anotada.');
    final clienteId = t.clienteId ?? await _clienteDe(db, nombre: t.nombreCliente, telefono: t.telefono);
    await _escribir(
      db,
      id,
      TurnosCompanion(
        estado: Value(EstadoTurno.confirmado.clave),
        clienteId: Value(clienteId),
        senaCentavos: Value(montoCentavos),
        senaEsEfectivo: Value(esEfectivo),
        senaEnCaja: Value(sesionCajaId != null),
        senaVence: const Value(null),
        origenDispositivo: Value(idDispositivoActual),
      ),
    );
    if (sesionCajaId != null) {
      await _ingresarSena(db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, monto: montoCentavos, esEfectivo: esEfectivo, nombre: t.nombreCliente);
    }
  });
}

/// Al abrir la caja: las señas que se anotaron en este equipo sin caja abierta entran ahora como ingreso (§21). Solo las de
/// este equipo, así dos equipos que abren su caja no la cuentan dos veces. Devuelve cuántas entraron.
Future<int> ingresarSenasPendientes(AppDatabase db, {required int sesionCajaId, required int usuarioId}) {
  return db.transaction(() async {
    final pendientes = await (db.select(db.turnos)
          ..where((t) =>
              t.senaEnCaja.equals(false) & t.senaCentavos.isBiggerThanValue(0) & t.origenDispositivo.equals(idDispositivoActual)))
        .get();
    for (final t in pendientes) {
      await _ingresarSena(db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, monto: t.senaCentavos, esEfectivo: t.senaEsEfectivo, nombre: t.nombreCliente);
      await _escribir(db, t.id, const TurnosCompanion(senaEnCaja: Value(true)));
    }
    return pendientes.length;
  });
}

/// Mueve el turno a [nuevoInicio] (y, si se pasa, a otro profesional). Lo que pise se guarda igual, como al darlo.
Future<void> moverTurno(AppDatabase db, int id, DateTime nuevoInicio, {int? profesionalId, bool cambiarProfesional = false}) async {
  final t = await _turno(db, id);
  if (!EstadoTurno.desdeClave(t.estado).abierto) throw ArgumentError('Este turno ya no está pendiente.');
  await _escribir(
    db,
    id,
    TurnosCompanion(
      inicio: Value(nuevoInicio),
      profesionalId: cambiarProfesional ? Value(profesionalId) : const Value.absent(),
    ),
  );
}

/// Cancela el turno y libera el horario. La seña ya cobrada se pierde o se devuelve según la configuración (§21): devolverla
/// necesita la caja abierta ([sesionCajaId]), por la misma caja por la que entró. Una seña que todavía no entró a ninguna caja
/// no se devuelve de ninguna: se borra. Devuelve lo que se devolvió.
Future<int> cancelarTurno(AppDatabase db, int id, {required int usuarioId, int? sesionCajaId}) {
  return db.transaction(() async {
    final t = await _turno(db, id);
    if (!EstadoTurno.desdeClave(t.estado).abierto) return 0;
    final config = await configAgendaActual(db);
    var devuelto = 0;
    if (t.senaCentavos > 0 && t.senaEnCaja) {
      devuelto = senaADevolverAlCancelar(senaCobradaCentavos: t.senaCentavos, config: config.sena);
      if (devuelto > 0) {
        if (sesionCajaId == null) throw ArgumentError('Para devolver la seña hace falta la caja abierta.');
        await registrarDevolucionSena(
          db,
          sesionCajaId: sesionCajaId,
          usuarioId: usuarioId,
          montoCentavos: devuelto,
          esEfectivo: t.senaEsEfectivo,
          motivo: 'Devolución de seña, turno de ${t.nombreCliente}',
        );
      }
    }
    final senaQueda = t.senaEnCaja ? t.senaCentavos : 0;
    await _escribir(
      db,
      id,
      TurnosCompanion(
        estado: Value(EstadoTurno.cancelado.clave),
        // Lo que no entró a ninguna caja deja de estar pendiente de entrar.
        senaCentavos: Value(senaQueda),
        senaEnCaja: const Value(true),
      ),
    );
    return devuelto;
  });
}

/// "No vino": libera el horario y suma una falta a la persona, sin bloquear nada (§21). La seña queda en la caja (como al
/// cancelar con "se pierde").
Future<void> marcarNoVino(AppDatabase db, int id) async {
  final t = await _turno(db, id);
  if (!EstadoTurno.desdeClave(t.estado).abierto) return;
  final clienteId = t.clienteId ?? await _clienteDe(db, nombre: t.nombreCliente, telefono: t.telefono);
  await _escribir(db, id, TurnosCompanion(estado: Value(EstadoTurno.noVino.clave), clienteId: Value(clienteId)));
}

/// La seña de un turno todavía abierto: cuánto y por qué caja. Un turno ya cobrado o liberado devuelve 0 (su seña ya se aplicó
/// o quedó), igual que `senaPendienteDe` de los encargues.
Future<({int centavos, bool esEfectivo})> senaPendienteDeTurno(AppDatabase db, int turnoId) async {
  final t = await (db.select(db.turnos)..where((x) => x.id.equals(turnoId))).getSingleOrNull();
  if (t == null || !EstadoTurno.desdeClave(t.estado).abierto) return (centavos: 0, esEfectivo: true);
  return (centavos: t.senaCentavos, esEfectivo: t.senaEsEfectivo);
}

/// Lo llama `registrarVenta` dentro de su transacción al cobrar el turno.
Future<void> marcarTurnoAtendido(AppDatabase db, int turnoId, {required int ventaId}) async {
  final t = await (db.select(db.turnos)..where((x) => x.id.equals(turnoId))).getSingleOrNull();
  if (t == null || !EstadoTurno.desdeClave(t.estado).abierto) {
    throw ArgumentError('Este turno ya no está pendiente: no se puede cobrar de nuevo.');
  }
  final clienteId = t.clienteId ?? await _clienteDe(db, nombre: t.nombreCliente, telefono: t.telefono);
  await _escribir(
    db,
    turnoId,
    TurnosCompanion(estado: Value(EstadoTurno.atendido.clave), ventaId: Value(ventaId), clienteId: Value(clienteId)),
  );
}

/// La línea de venta del servicio del turno, al precio de HOY (Regla 4, como un encargue).
Future<LineaVenta> lineaDeTurno(AppDatabase db, int turnoId) async {
  final t = await _turno(db, turnoId);
  final servicio = t.servicioId == null
      ? null
      : await (db.select(db.productos)..where((p) => p.id.equals(t.servicioId!))).getSingleOrNull();
  if (servicio == null || servicio.precioCentavos == null) {
    throw ArgumentError('El servicio de este turno ya no está o no tiene precio: cobralo desde Vender.');
  }
  return lineaDesdeProducto(servicio, cantidad: 1);
}

/// Cuánto se cobra hoy el turno y qué parte cubre la seña.
Future<AplicacionSena> cuentaDeTurno(AppDatabase db, int turnoId) async {
  final linea = await lineaDeTurno(db, turnoId);
  final sena = await senaPendienteDeTurno(db, turnoId);
  return aplicarSena(totalCentavos: Venta(lineas: [linea]).subtotalCentavos, senaCentavos: sena.centavos);
}

/// Los turnos de hoy en adelante que esperan seña y ya vencieron: se cancelan solos y liberan el horario (§21: "hasta que
/// pague o venza"). Devuelve cuántos.
Future<int> liberarSenasVencidas(AppDatabase db, {DateTime? ahora}) async {
  final momento = ahora ?? DateTime.now();
  final vencidos = await (db.select(db.turnos)
        ..where((t) => t.estado.equals(EstadoTurno.esperandoSena.clave) & t.senaVence.isSmallerThanValue(momento)))
      .get();
  for (final t in vencidos) {
    await _escribir(db, t.id, TurnosCompanion(estado: Value(EstadoTurno.cancelado.clave), nota: Value('${t.nota == null ? '' : '${t.nota} · '}No pagó la seña a tiempo')));
  }
  return vencidos.length;
}

/// Si hay caja abierta (para tomar o devolver una seña).
Future<int?> sesionAbiertaId(AppDatabase db) async => (await sesionAbierta(db))?.id;
