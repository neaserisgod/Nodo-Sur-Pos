// Los datos del tablero de arriba de la Agenda (las cuentas, en `domain/tablero_agenda.dart`). Se lee de la base del equipo
// cada vez que la Agenda se recarga: es poco (los turnos de hoy, los servicios y los insumos) y no hay nada que precalcular.

import 'package:drift/drift.dart';

import '../domain/tablero_agenda.dart';
import '../domain/turnos.dart';
import 'database.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_servicios.dart' show listarInsumos;
import 'repositorio_turnos.dart';

class TableroAgenda {
  const TableroAgenda({
    required this.turnos,
    required this.huecosHoy,
    required this.esperanSena,
    required this.insumosBajos,
    required this.textoHuecos,
  });

  /// Los turnos de hoy, con el precio de hoy de su servicio.
  final List<TurnoDelTablero> turnos;

  /// Cuántos huecos libres (tramos seguidos) quedan hoy.
  final int huecosHoy;
  final int esperanSena;

  /// Los insumos por debajo de su mínimo.
  final List<String> insumosBajos;

  /// Lo que se comparte con "Compartir huecos" (null: no queda ningún hueco en los próximos días).
  final String? textoHuecos;
}

/// Cuántos días con lugar entran en el texto para compartir, y hasta cuántos días adelante se buscan.
const diasACompartir = 3;
const _diasABuscar = 7;

Future<TableroAgenda> tableroAgenda(AppDatabase db, {DateTime? ahora}) async {
  final momento = ahora ?? DateTime.now();
  final hoy = DateTime(momento.year, momento.month, momento.day);

  final servicios = await (db.select(db.productos)..where((p) => p.esServicio.equals(true) & p.activo.equals(true))).get();
  final precios = {for (final s in servicios) s.id: s.precioCentavos ?? 0};
  final turnosHoy = await turnosDelDia(db, hoy);
  final turnos = [
    for (final t in turnosHoy)
      if (t.estado != EstadoTurno.cancelado)
        TurnoDelTablero(
          inicio: t.inicio,
          duracionMin: t.turno.duracionMinutos,
          cliente: t.turno.nombreCliente,
          servicio: t.turno.servicioNombre,
          ocupa: t.estado.ocupa,
          atendido: t.estado == EstadoTurno.atendido,
          esperaSena: t.estado == EstadoTurno.esperandoSena,
          precioCentavos: precios[t.turno.servicioId] ?? 0,
          senaCentavos: t.turno.senaCentavos,
          faltas: t.faltas,
        ),
  ];

  final config = await configAgendaActual(db);
  // El hueco más chico que vale la pena ofrecer: lo que dura el servicio más corto.
  final duraciones = [for (final s in servicios) if ((s.duracionMinutos ?? 0) > 0) s.duracionMinutos!];
  final duracion = duraciones.isEmpty ? 30 : duraciones.reduce((a, b) => a < b ? a : b);

  // Con varios profesionales, un horario está libre si al menos uno lo tiene libre. Cuentan solo los que atienden (tienen
  // turnos esta semana): la cuenta de quien solo administra no tiene agenda y ofrecería todo el día.
  final semana = await turnosEntre(db, desde: hoy, hasta: DateTime(hoy.year, hoy.month, hoy.day + _diasABuscar), incluirLiberados: false);
  final profesionales = {for (final t in semana) if (t.turno.profesionalId != null) t.turno.profesionalId!};

  Future<List<DateTime>> libresDe(DateTime dia) async {
    if (profesionales.length < 2) return horariosLibresDelDia(db, dia, duracionMin: duracion, ahora: momento);
    final union = <DateTime>{};
    for (final p in profesionales) {
      union.addAll(await horariosLibresDelDia(db, dia, duracionMin: duracion, profesionalId: p, ahora: momento));
    }
    return union.toList()..sort();
  }

  final dias = <({DateTime dia, List<DateTime> comienzos})>[];
  var huecosHoy = 0;
  for (var i = 0; i < _diasABuscar && dias.length < diasACompartir; i++) {
    final dia = DateTime(hoy.year, hoy.month, hoy.day + i);
    final comienzos = comienzosDeHuecos(await libresDe(dia), pasoMin: config.pasoMinutos);
    if (i == 0) huecosHoy = comienzos.length;
    if (comienzos.isNotEmpty) dias.add((dia: dia, comienzos: comienzos));
  }

  final negocio = await configuracionNegocioActual(db);
  final insumos = await listarInsumos(db);
  return TableroAgenda(
    turnos: turnos,
    huecosHoy: huecosHoy,
    esperanSena: turnos.where((t) => t.esperaSena).length,
    insumosBajos: [for (final i in insumos) if (i.pocoStock) i.producto.nombre],
    textoHuecos: textoCompartirHuecos(negocio: negocio.nombreComercio, emoji: emojiDeRubro(negocio.rubro), dias: dias, hoy: hoy),
  );
}
