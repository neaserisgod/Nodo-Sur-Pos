// Los turnos del bot de WhatsApp en la Agenda (negocios de servicios; `docs/PLAN-SERVICIOS.md` etapa 5, `REGLAS-NEGOCIO.md` §21).
// Lo corre el equipo que sube la sync a la nube, al terminar cada vuelta (como el catálogo del bot, `catalogo_bot_nube.dart`): uno
// solo a la vez, así un turno del bot no entra dos veces a la Agenda con dos `global_id` distintos.
//
// Tres cosas por vuelta:
//  1. BAJAR los turnos que dio o cambió el bot (`/api/bot/turnos`, con cursor) y ponerlos en la Agenda: entran confirmados, o
//     "esperando seña" ocupando el horario (§21). Si el cliente lo canceló o lo cambió por WhatsApp, se aplica acá.
//  2. AVISAR lo que la dueña hizo en la app con un turno del bot (lo movió, lo canceló, lo cobró, no vino, anotó la seña): el bot
//     le avisa al cliente.
//  3. PUBLICAR lo que ocupa la Agenda (los turnos cargados en la app, sin nombres ni teléfonos): el bot no ofrece esos horarios.
//  4. Llevar al bot los SERVICIOS, el horario de atención y la seña del negocio (El dueño, 2026-10-10: los datos del negocio
//     son los del bot, sin una configuración aparte). Solo si quien usa este equipo puede configurar el bot y el bot ya tiene su
//     configuración básica (los números, en Más › Bot de WhatsApp), y solo cuando algo de eso cambió.
//
// Nunca tira: un error se ve en la próxima vuelta, y la Agenda funciona igual sin el bot.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_configuracion.dart' show modulosNegocioActuales;
import '../data/repositorio_turnos.dart';
import '../domain/bot_whatsapp.dart';
import '../domain/forma_de_trabajo.dart';
import '../domain/turnos.dart';
import 'avisos_bot.dart';
import 'cuenta_nube.dart';

const _claveCursor = 'turnosBot.cursor';
const _claveHuellas = 'turnosBot.huellas';

/// El estado de un turno como lo dice el sitio.
String estadoEnSitio(EstadoTurno e) => switch (e) {
      EstadoTurno.esperandoSena => 'esperando_sena',
      EstadoTurno.confirmado => 'confirmado',
      EstadoTurno.atendido => 'atendido',
      EstadoTurno.noVino => 'no_vino',
      EstadoTurno.cancelado => 'cancelado',
    };

EstadoTurno? estadoDesdeSitio(Object? s) => switch (s) {
      'esperando_sena' => EstadoTurno.esperandoSena,
      'confirmado' => EstadoTurno.confirmado,
      'atendido' => EstadoTurno.atendido,
      'no_vino' => EstadoTurno.noVino,
      'cancelado' => EstadoTurno.cancelado,
      _ => null,
    };

class SincronizadorTurnosBot {
  SincronizadorTurnosBot({required this.db, required this.cliente, DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now {
    _aviso = avisosTurnoBot.listen((_) {
      final token = _ultimoToken;
      if (token != null) unawaited(vuelta(token));
    });
  }

  final AppDatabase db;
  final ClienteNube cliente;
  final DateTime Function() _ahora;
  StreamSubscription<String>? _aviso;

  static const revisarPlanCada = Duration(hours: 1);
  EstadoBot? _estado;
  DateTime? _planRevisado;
  String? _ultimaConfig;
  String? _ultimoToken;
  String? _ultimosOcupados;
  Future<void>? _enCurso;

  void cerrar() => _aviso?.cancel();

  /// Una vuelta entera. Si ya hay una corriendo (un aviso en vivo en el medio de la vuelta de la sync), espera a esa.
  Future<void> vuelta(String token) {
    _ultimoToken = token;
    return _enCurso ??= _vuelta(token).whenComplete(() => _enCurso = null);
  }

  Future<void> _vuelta(String token) async {
    try {
      if ((await modulosNegocioActuales(db)).forma != FormaDeTrabajo.servicios) return;
      final ahora = _ahora();
      if (_estado == null || _planRevisado == null || ahora.difference(_planRevisado!) >= revisarPlanCada) {
        _estado = await cliente.estadoBot(token);
        _planRevisado = ahora;
      }
      if (_estado?.tieneBot != true) return;
      final prefs = await SharedPreferences.getInstance();
      final huellas = _leerHuellas(prefs);
      await _bajar(token, prefs, huellas);
      await _avisarCambios(token, huellas);
      await prefs.setString(_claveHuellas, jsonEncode(huellas));
      await _publicarOcupados(token);
      if (_estado!.puedeConfigurar) await _publicarConfig(token);
    } catch (_) {
      // Sin red, sin plan o el sitio caído: en la próxima vuelta.
    }
  }

  Map<String, String> _leerHuellas(SharedPreferences prefs) {
    try {
      return (jsonDecode(prefs.getString(_claveHuellas) ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// Cómo está un turno del bot: si cambia entre vueltas, la dueña hizo algo en la app y el bot se tiene que enterar.
  static String huellaDe(Turno t) =>
      '${t.estado}|${t.inicio.millisecondsSinceEpoch}|${t.inicio.add(Duration(minutes: t.duracionMinutos)).millisecondsSinceEpoch}';

  Future<void> _bajar(String token, SharedPreferences prefs, Map<String, String> huellas) async {
    var desde = prefs.getInt(_claveCursor) ?? 0;
    for (var i = 0; i < 20; i++) {
      final r = await cliente.turnosBot(token, desde: desde);
      for (final x in r.turnos) {
        if (x['origen'] != 'bot') continue; // lo de la app ya está acá
        final id = await _aplicar(x);
        if (id != null) huellas['${x['id']}'] = huellaDe(await (db.select(db.turnos)..where((t) => t.id.equals(id))).getSingle());
      }
      desde = r.hasta;
      await prefs.setInt(_claveCursor, desde);
      if (!r.mas) break;
    }
  }

  /// Pone en la Agenda (o actualiza) un turno del bot. Devuelve su id local, o null si no se pudo (el servicio no existe acá).
  Future<int?> _aplicar(Map<String, dynamic> x) async {
    final idRemoto = x['id'];
    final estado = estadoDesdeSitio(x['estado']);
    final inicioMs = x['inicio'], finMs = x['fin'];
    if (idRemoto is! String || estado == null || inicioMs is! int || finMs is! int) return null;
    final inicio = DateTime.fromMillisecondsSinceEpoch(inicioMs);
    final existente = await (db.select(db.turnos)..where((t) => t.idRemoto.equals(idRemoto))).getSingleOrNull();
    if (existente == null) {
      if (!estado.abierto) return null; // uno que el bot ya canceló antes de llegar acá no hace falta
      final servicio = await _servicioDe(x['servicio']);
      if (servicio == null) return null;
      final cliente = x['cliente'] is Map ? (x['cliente'] as Map) : const {};
      final usuario = await (db.select(db.usuarios)..limit(1)).getSingleOrNull();
      if (usuario == null) return null;
      final vence = x['senaVence'];
      return crearTurno(
        db,
        servicioId: servicio.id,
        inicio: inicio,
        duracionMinutos: ((finMs - inicioMs) ~/ 60000).clamp(1, 24 * 60),
        nombreCliente: '${cliente['nombre'] ?? 'Cliente de WhatsApp'}',
        telefono: cliente['telefono'] is String ? cliente['telefono'] as String : null,
        usuarioId: usuario.id,
        nota: x['nota'] is String ? x['nota'] as String : null,
        senaPedidaCentavos: x['senaPedidaCentavos'] is int ? x['senaPedidaCentavos'] as int : null,
        estado: estado,
        senaVence: vence is int ? DateTime.fromMillisecondsSinceEpoch(vence) : null,
        origen: 'BOT',
        idRemoto: idRemoto,
      );
    }
    // Ya está: lo que el cliente hizo por WhatsApp (canceló, lo cambió, la dueña aprobó la seña ahí). Lo que ya se cerró acá
    // (cobrado, no vino, cancelado) no se reabre.
    final local = EstadoTurno.desdeClave(existente.estado);
    if (!local.abierto) return existente.id;
    if (estado == EstadoTurno.cancelado) {
      await cancelarTurno(db, existente.id, usuarioId: existente.usuarioId);
    } else if (estado == EstadoTurno.confirmado && local == EstadoTurno.esperandoSena) {
      await (db.update(db.turnos)..where((t) => t.id.equals(existente.id)))
          .write(TurnosCompanion(estado: Value(EstadoTurno.confirmado.clave), actualizadoEn: Value(DateTime.now())));
    }
    if (estado.abierto && existente.inicio != inicio) await moverTurno(db, existente.id, inicio);
    return existente.id;
  }

  Future<Producto?> _servicioDe(Object? s) async {
    if (s is! Map) return null;
    final gid = s['gid'];
    if (gid is String) {
      final porGid = await (db.select(db.productos)..where((p) => p.globalId.equals(gid) & p.esServicio.equals(true))).getSingleOrNull();
      if (porGid != null) return porGid;
    }
    final nombre = '${s['nombre'] ?? ''}'.trim().toLowerCase();
    final servicios = await (db.select(db.productos)..where((p) => p.esServicio.equals(true))).get();
    return servicios.where((p) => p.nombre.trim().toLowerCase() == nombre).firstOrNull;
  }

  Future<void> _avisarCambios(String token, Map<String, String> huellas) async {
    final delBot = await (db.select(db.turnos)..where((t) => t.origen.equals('BOT') & t.idRemoto.isNotNull())).get();
    for (final t in delBot) {
      final ahora = huellaDe(t);
      if (huellas[t.idRemoto!] == ahora) continue;
      final fin = t.inicio.add(Duration(minutes: t.duracionMinutos));
      try {
        await cliente.cambiarTurnoBot(
          token,
          t.idRemoto!,
          estado: estadoEnSitio(EstadoTurno.desdeClave(t.estado)),
          inicio: t.inicio.millisecondsSinceEpoch,
          fin: fin.millisecondsSinceEpoch,
        );
        huellas[t.idRemoto!] = ahora;
      } on ErrorNube catch (e) {
        if (e.codigo == 'no_existe') huellas[t.idRemoto!] = ahora; // ya no está en el sitio: nada que avisar
      }
    }
  }

  Future<void> _publicarConfig(String token) async {
    final agenda = await configAgendaActual(db);
    final servicios = [
      for (final p in await (db.select(db.productos)
            ..where((p) => p.esServicio.equals(true) & p.activo.equals(true) & p.globalId.isNotNull())
            ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
          .get())
        if ((p.duracionMinutos ?? 0) > 0 && (p.precioCentavos ?? 0) > 0)
          ServicioParaBot(
            gid: p.globalId!,
            nombre: p.nombre,
            duracionMinutos: p.duracionMinutos!,
            precioCentavos: p.precioCentavos!,
            senaCentavos: senaDeServicio(precioCentavos: p.precioCentavos!, pideSena: p.pideSena, config: agenda.sena),
          ),
    ];
    if (servicios.isEmpty) return;
    // Lo que entra, para no pedirle la configuración al sitio en cada vuelta si nada cambió acá.
    final entrada = jsonEncode([
      for (final s in servicios) [s.gid, s.nombre, s.duracionMinutos, s.precioCentavos, s.senaCentavos],
      agenda.horario.toJson(),
      agenda.pasoMinutos,
      agenda.aliasSena,
      agenda.titularSena,
    ]);
    if (entrada == _ultimaConfig) return;
    final actual = await cliente.configBot(token);
    // Sin la configuración básica (los números) el bot no puede arrancar: eso se carga una vez en Más › Bot de WhatsApp.
    final anterior = actual.config;
    if (anterior == null) return;
    final nueva = configBotConServicios(
      anterior,
      servicios: servicios,
      horario: agenda.horario,
      pasoMinutos: agenda.pasoMinutos,
      aliasSena: agenda.aliasSena,
      titularSena: agenda.titularSena,
    );
    if (jsonEncode(nueva) != jsonEncode(anterior)) await cliente.guardarConfigBot(token, nueva);
    _ultimaConfig = entrada;
  }

  Future<void> _publicarOcupados(String token) async {
    final hoy = _ahora();
    final desde = DateTime(hoy.year, hoy.month, hoy.day);
    final propios = await (db.select(db.turnos)
          ..where((t) => t.origen.equals('APP') & t.inicio.isBiggerOrEqualValue(desde) & t.globalId.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.inicio)])
          ..limit(1000))
        .get();
    final lista = [
      for (final t in propios)
        if (EstadoTurno.desdeClave(t.estado).ocupa)
          <String, Object>{
            'id': t.globalId!,
            'inicio': t.inicio.millisecondsSinceEpoch,
            'fin': t.inicio.add(Duration(minutes: t.duracionMinutos)).millisecondsSinceEpoch,
            'estado': estadoEnSitio(EstadoTurno.desdeClave(t.estado)),
          },
    ];
    final huella = jsonEncode(lista);
    if (huella == _ultimosOcupados) return;
    await cliente.publicarOcupadosBot(token, lista);
    _ultimosOcupados = huella;
  }
}
