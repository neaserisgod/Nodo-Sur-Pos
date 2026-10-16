// Los datos que ve el asistente con IA y lo que hace cuando la persona confirma una acción (`domain/asistente_ia.dart`).
// Todo se vuelve a validar contra la base justo antes de escribir: entre la respuesta de la IA y el "Sí" pudo entrar un turno
// del bot, cerrarse la caja o cobrarse el turno.

import 'package:drift/drift.dart';

import '../domain/asistente_ia.dart';
import '../domain/turnos.dart';
import 'database.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_gastos.dart';
import 'repositorio_turnos.dart';
import 'repositorio_ventas.dart' show sesionAbierta;

/// Días hacia atrás y hacia adelante de agenda que ve la IA, y cuántos días de huecos.
const _diasAtras = 7;
const _diasAdelante = 14;
const _diasDeHuecos = 7;

Future<CobrosIa> _cobradoEntre(AppDatabase db, DateTime desde, DateTime hasta) async {
  final ventas = await (db.select(db.ventas)
        ..where((v) => v.fecha.isBiggerOrEqualValue(desde) & v.fecha.isSmallerThanValue(hasta) & v.anuladaEn.isNull()))
      .get();
  return (centavos: ventas.fold(0, (a, v) => a + v.totalCentavos), cobros: ventas.length);
}

Future<DatosIa> datosParaAsistenteIa(AppDatabase db, {DateTime? ahora}) async {
  final momento = ahora ?? DateTime.now();
  final hoy = DateTime(momento.year, momento.month, momento.day);
  final negocio = await configuracionNegocioActual(db);
  final config = configAgendaDe(negocio);

  final productos = await (db.select(db.productos)..where((p) => p.esServicio.equals(true) & p.activo.equals(true))).get();
  final servicios = [
    for (final p in productos)
      ServicioIa(id: p.id, nombre: p.nombre, precioCentavos: p.precioCentavos ?? 0, duracionMin: p.duracionMinutos ?? 0),
  ];

  final agenda = await turnosEntre(
    db,
    desde: DateTime(hoy.year, hoy.month, hoy.day - _diasAtras),
    hasta: DateTime(hoy.year, hoy.month, hoy.day + _diasAdelante),
    incluirLiberados: false,
  );
  final turnos = [
    for (final t in agenda)
      TurnoIa(
        id: t.turno.id,
        inicio: t.inicio,
        duracionMin: t.turno.duracionMinutos,
        servicio: t.turno.servicioNombre,
        cliente: t.turno.nombreCliente,
        estado: t.estado,
        senaCentavos: t.turno.senaCentavos,
      ),
  ];

  // Como el tablero de la Agenda: el hueco que vale la pena ofrecer es lo que dura el servicio más corto.
  final duraciones = [for (final s in servicios) if (s.duracionMin > 0) s.duracionMin];
  final duracion = duraciones.isEmpty ? 30 : duraciones.reduce((a, b) => a < b ? a : b);
  final libres = <DateTime, List<DateTime>>{};
  for (var i = 0; i < _diasDeHuecos; i++) {
    final dia = DateTime(hoy.year, hoy.month, hoy.day + i);
    libres[dia] = await horariosLibresDelDia(db, dia, duracionMin: duracion, ahora: momento);
  }

  final inicioMes = DateTime(hoy.year, hoy.month);
  final finMes = DateTime(hoy.year, hoy.month + 1);
  final porServicio = db.lineasDeVenta.id.count();
  final delMes = await (db.selectOnly(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
    innerJoin(db.productos, db.productos.id.equalsExp(db.lineasDeVenta.productoId)),
  ])
        ..addColumns([db.lineasDeVenta.nombreProductoFoto, porServicio])
        ..where(db.ventas.fecha.isBiggerOrEqualValue(inicioMes) & db.ventas.anuladaEn.isNull() & db.productos.esServicio.equals(true))
        ..groupBy([db.lineasDeVenta.nombreProductoFoto]))
      .map((f) => MapEntry(f.read(db.lineasDeVenta.nombreProductoFoto) ?? '', f.read(porServicio) ?? 0))
      .get();

  return DatosIa(
    negocio: negocio.nombreComercio,
    ahora: momento,
    horario: config.horario,
    servicios: servicios,
    turnos: turnos,
    libres: libres,
    cajaAbierta: await sesionAbierta(db) != null,
    hoy: await _cobradoEntre(db, hoy, hoy.add(const Duration(days: 1))),
    mes: await _cobradoEntre(db, inicioMes, finMes),
    mesAnterior: await _cobradoEntre(db, DateTime(hoy.year, hoy.month - 1), inicioMes),
    serviciosDelMes: Map.fromEntries(delMes),
    pasoMin: config.pasoMinutos,
  );
}

Future<void> _verificarLibre(AppDatabase db, DateTime inicio, int duracionMin, {int? salvoTurnoId}) async {
  final dia = DateTime(inicio.year, inicio.month, inicio.day);
  final libres = await horariosLibresDelDia(db, dia, duracionMin: duracionMin, salvoTurnoId: salvoTurnoId);
  if (!libres.contains(inicio)) {
    throw ArgumentError('${fechaHoraIa(inicio)} ya no está libre o queda fuera del horario. Elegí otra hora o hacelo desde la Agenda.');
  }
}

/// Hace lo que la persona confirmó. Devuelve el aviso para mostrar; [ArgumentError] con el motivo si ya no se puede.
/// [IrAIa] no pasa por acá: es navegación, la resuelve la pantalla.
Future<String> ejecutarAccionIa(AppDatabase db, AccionIa accion, {required int usuarioId, DateTime? ahora}) async {
  final momento = ahora ?? DateTime.now();
  switch (accion) {
    case DarTurnoIa(:final servicio, :final inicio, :final cliente):
      if (inicio.isBefore(momento)) throw ArgumentError('Esa hora ya pasó.');
      await _verificarLibre(db, inicio, servicio.duracionMin);
      await crearTurno(db, servicioId: servicio.id, inicio: inicio, nombreCliente: cliente, usuarioId: usuarioId, sesionCajaId: (await sesionAbierta(db))?.id);
      return 'Turno anotado: $cliente, ${fechaHoraIa(inicio)}';
    case MoverTurnoIa(:final turno, :final inicio):
      if (inicio.isBefore(momento)) throw ArgumentError('Esa hora ya pasó.');
      await _verificarLibre(db, inicio, turno.duracionMin, salvoTurnoId: turno.id);
      await moverTurno(db, turno.id, inicio);
      return 'Turno de ${turno.cliente} movido a ${fechaHoraIa(inicio)}';
    case CancelarTurnoIa(:final turno):
      final fila = await (db.select(db.turnos)..where((t) => t.id.equals(turno.id))).getSingleOrNull();
      if (fila == null || !EstadoTurno.desdeClave(fila.estado).abierto) throw ArgumentError('Ese turno ya no está pendiente.');
      // Con seña hay que decidir la devolución (y si fue por link, devolverla por Mercado Pago): eso lo resuelve la Agenda.
      if (fila.senaCentavos > 0) throw ArgumentError('${fila.nombreCliente} dejó seña: cancelalo desde la Agenda, que ahí se resuelve la devolución.');
      await cancelarTurno(db, turno.id, usuarioId: usuarioId);
      return 'Turno de ${turno.cliente} cancelado';
    case GastoIa(:final montoCentavos, :final motivo, :final porMercadoPago):
      final sesion = await sesionAbierta(db);
      if (sesion == null) throw ArgumentError('La caja está cerrada: empezá el día para anotar el gasto.');
      await registrarGastoRapido(
        db,
        sesionCajaId: sesion.id,
        usuarioId: usuarioId,
        montoCentavos: montoCentavos,
        medio: porMercadoPago ? MedioGasto.mercadoPago : MedioGasto.cajonNormal,
        motivo: motivo,
      );
      return 'Gasto anotado: ${describirAccionIa(accion)}';
    case IrAIa():
      throw ArgumentError('Ir a una pantalla no se ejecuta acá.');
  }
}
