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
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_configuracion.dart' show modulosNegocioActuales;
import '../data/repositorio_turnos.dart';
import '../domain/bot_whatsapp.dart';
import '../domain/forma_de_trabajo.dart';
import '../domain/normalizacion_texto.dart';
import '../domain/turnos.dart';
import 'avisos_bot.dart';
import '../edicion.dart';
import 'cuenta_nube.dart';

const _claveCursor = 'turnosBot.cursor';
const _claveHuellas = 'turnosBot.huellas';
const _claveSinCargar = 'turnosBot.sinCargar';

/// Los turnos del bot que bajaron pero no se pudieron poner en la Agenda, con el motivo (El dueño, 2026-10-13: "se confirma el
/// turno, se confirma la seña, pero en la aplicación no aparece"). Antes se salteaban callados y el cursor seguía de largo: no se
/// volvían a intentar nunca. Ahora se guardan, se reintentan en cada vuelta y la Agenda los muestra en "Para atender".
final ValueNotifier<List<String>> turnosBotSinCargar = ValueNotifier(const []);

/// Un turno del bot que no se pudo cargar acá, y por qué (para mostrarlo tal cual).
class _NoSeCarga implements Exception {
  const _NoSeCarga(this.motivo);
  final String motivo;
}

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
  SincronizadorTurnosBot({required this.db, required this.cliente, DateTime Function()? ahora, this.alBajar})
      : _ahora = ahora ?? DateTime.now {
    _aviso = avisosTurnoBot.listen((_) {
      final token = _ultimoToken;
      if (token != null) unawaited(vuelta(token));
    });
  }

  final AppDatabase db;
  final ClienteNube cliente;

  /// Se llama cuando bajó al menos un turno nuevo o cambiado (uno que dio el bot, una seña que se pagó): las pantallas abiertas
  /// se redibujan al toque. Sin esto la Agenda se enteraba recién al cambiar de pantalla (El dueño, 2026-10-13: "quiero que
  /// aparezca enseguida, apenas se confirme el turno").
  final void Function()? alBajar;
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

  /// Una vuelta entera. Si ya hay una corriendo, al terminar esa se hace otra: un aviso en vivo que llega en el medio (el bot dio
  /// un turno, se pagó una seña) puede ser de algo que la vuelta en curso ya no va a ver, porque pidió la lista antes. Sumarse a la
  /// que corre lo perdía hasta la próxima vuelta de la sync (El dueño, 2026-10-13: "tardó en aparecer, pero apareció").
  Future<void> vuelta(String token) {
    _ultimoToken = token;
    final enCurso = _enCurso;
    if (enCurso != null) {
      _repetir = true;
      return enCurso;
    }
    return _enCurso = _correr();
  }

  var _repetir = false;

  Future<void> _correr() async {
    try {
      do {
        _repetir = false;
        await _vuelta(_ultimoToken!);
      } while (_repetir);
    } finally {
      _enCurso = null;
    }
  }

  Future<void> _vuelta(String token) async {
    try {
      if (!esEdicionServicios && (await modulosNegocioActuales(db)).forma != FormaDeTrabajo.servicios) return;
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
    var bajoAlgo = false;
    // Los que quedaron sin cargar en otra vuelta (por id del sitio: si vuelve a bajar uno más nuevo, gana ese).
    final pendientes = <String, ({Map<String, dynamic> turno, String motivo})>{};
    try {
      for (final p in (jsonDecode(prefs.getString(_claveSinCargar) ?? '[]') as List).cast<Map>()) {
        final t = (p['turno'] as Map).cast<String, dynamic>();
        pendientes['${t['id']}'] = (turno: t, motivo: '${p['motivo']}');
      }
    } catch (_) {
      // guardado roto: se arranca de cero
    }

    Future<void> cargar(Map<String, dynamic> x) async {
      try {
        final local = await _aplicar(x, huellas);
        pendientes.remove('${x['id']}');
        if (local != null) {
          huellas['${x['id']}'] = huellaDe(await (db.select(db.turnos)..where((t) => t.id.equals(local))).getSingle());
          bajoAlgo = true;
        }
      } on _NoSeCarga catch (e) {
        pendientes['${x['id']}'] = (turno: x, motivo: e.motivo);
      } catch (e) {
        // Uno que no se puede aplicar no frena a los demás, pero tampoco se pierde: se reintenta en la próxima vuelta.
        pendientes['${x['id']}'] = (turno: x, motivo: e is ArgumentError ? '${e.message}' : '$e');
      }
    }

    for (final x in [for (final p in pendientes.values) p.turno]) {
      await cargar(x);
    }
    for (var i = 0; i < 20; i++) {
      final r = await cliente.turnosBot(token, desde: desde);
      for (final x in r.turnos) {
        if (x['origen'] != 'bot') continue; // lo de la app ya está acá
        await cargar(x);
      }
      desde = r.hasta;
      await prefs.setInt(_claveCursor, desde);
      if (!r.mas) break;
    }
    // Un turno que ya pasó hace más de un día no se va a cargar nunca: no se arrastra para siempre.
    final limite = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    pendientes.removeWhere((_, p) => p.turno['fin'] is int && (p.turno['fin'] as int) < limite);
    await prefs.setString(_claveSinCargar, jsonEncode([for (final p in pendientes.values) {'turno': p.turno, 'motivo': p.motivo}]));
    final motivos = [for (final p in pendientes.values) p.motivo];
    if (!_mismaLista(motivos, turnosBotSinCargar.value)) turnosBotSinCargar.value = motivos;
    if (bajoAlgo) alBajar?.call();
  }

  static bool _mismaLista(List<String> a, List<String> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// Pone en la Agenda (o actualiza) un turno del bot. Devuelve su id local, o null si no se pudo (el servicio no existe acá).
  Future<int?> _aplicar(Map<String, dynamic> x, Map<String, String> huellas) async {
    final idRemoto = x['id'];
    final estado = estadoDesdeSitio(x['estado']);
    final inicioMs = x['inicio'], finMs = x['fin'];
    if (idRemoto is! String || estado == null || inicioMs is! int || finMs is! int) return null;
    final inicio = DateTime.fromMillisecondsSinceEpoch(inicioMs);
    // El primero que entró, si quedó dos veces (antes de `globalIdDeTurnoRemoto`).
    final existente = await (db.select(db.turnos)
          ..where((t) => t.idRemoto.equals(idRemoto))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (existente == null) {
      if (!estado.abierto) return null; // uno que el bot ya canceló antes de llegar acá no hace falta
      final servicio = await _servicioDe(x['servicio']);
      final cliente = x['cliente'] is Map ? (x['cliente'] as Map) : const {};
      final quien = '${cliente['nombre'] ?? 'Un cliente'}';
      if (servicio == null) {
        final nombre = x['servicio'] is Map ? '${(x['servicio'] as Map)['nombre'] ?? ''}' : '';
        throw _NoSeCarga('Turno de $quien: el servicio «$nombre» no está en Servicios. Cargalo con ese nombre y el turno aparece solo.');
      }
      final usuario = await (db.select(db.usuarios)..limit(1)).getSingleOrNull();
      if (usuario == null) throw _NoSeCarga('Turno de $quien: falta elegir usuario en este equipo.');
      final vence = x['senaVence'];
      final nuevo = await crearTurno(
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
      await _senaPagadaPorLink(nuevo, usuario.id, x['senaPagada']);
      return nuevo;
    }
    // Ya está: lo que el cliente hizo por WhatsApp (canceló, lo cambió, la dueña aprobó la seña ahí). Lo que ya se cerró acá
    // (cobrado, no vino, cancelado) no se reabre.
    final local = EstadoTurno.desdeClave(existente.estado);
    if (!local.abierto) return existente.id;
    // La dueña lo cambió acá (lo movió, lo canceló) y todavía no se le avisó al bot: gana lo de acá hasta que salga en
    // `_avisarCambios`. Si no, una bajada del mismo turno en el medio (el bot tocó algo) lo volvía a la hora vieja y el aviso
    // al cliente no salía nunca (El dueño, 2026-10-13: "al reagendar un turno no notifica a la persona"). La seña sí se anota.
    // Una cancelación del cliente sí entra: el turno ya no va a pasar, haya hecho lo que haya hecho la dueña.
    final previa = huellas[idRemoto];
    if (previa != null && previa != huellaDe(existente) && estado != EstadoTurno.cancelado) {
      if (estado.abierto) await _senaPagadaPorLink(existente.id, existente.usuarioId, x['senaPagada']);
      return null; // sin tocar su huella: así `_avisarCambios` todavía ve el cambio y lo manda
    }
    if (estado == EstadoTurno.cancelado) {
      try {
        await cancelarTurno(db, existente.id, usuarioId: existente.usuarioId, sesionCajaId: await sesionAbiertaId(db));
      } on ArgumentError {
        // Hay que devolver la seña y no hay caja abierta: el turno se cancela igual (libera el horario) y la seña queda para
        // que la dueña la devuelva a mano. Si no, este turno frenaría la vuelta entera para siempre.
        await (db.update(db.turnos)..where((t) => t.id.equals(existente.id)))
            .write(TurnosCompanion(estado: Value(EstadoTurno.cancelado.clave), actualizadoEn: Value(DateTime.now())));
      }
    } else if (estado == EstadoTurno.confirmado && local == EstadoTurno.esperandoSena) {
      await (db.update(db.turnos)..where((t) => t.id.equals(existente.id)))
          .write(TurnosCompanion(estado: Value(EstadoTurno.confirmado.clave), actualizadoEn: Value(DateTime.now())));
    }
    if (estado.abierto) await _senaPagadaPorLink(existente.id, existente.usuarioId, x['senaPagada']);
    if (estado.abierto && existente.inicio != inicio) await moverTurno(db, existente.id, inicio);
    return existente.id;
  }

  /// La seña que la clienta pagó con el link de Mercado Pago del bot (`senaPagada` del sitio): entra a la caja como Mercado Pago, una
  /// sola vez. Sin caja abierta queda anotada y entra al abrirla (`ingresarSenasPendientes`). Una pagada tarde (el horario ya se
  /// había liberado) no entra: la dueña decide desde la notificación.
  Future<void> _senaPagadaPorLink(int turnoId, int usuarioId, Object? pagada) async {
    if (pagada is! Map || pagada['tarde'] == true) return;
    final centavos = pagada['centavos'];
    if (centavos is! int || centavos <= 0) return;
    final t = await (db.select(db.turnos)..where((x) => x.id.equals(turnoId))).getSingleOrNull();
    if (t == null || t.senaCentavos > 0 || !EstadoTurno.desdeClave(t.estado).abierto) return;
    await registrarSenaDeTurno(db, turnoId, montoCentavos: centavos, esEfectivo: false, usuarioId: usuarioId, sesionCajaId: await sesionAbiertaId(db));
  }

  Future<Producto?> _servicioDe(Object? s) async {
    if (s is! Map) return null;
    final gid = s['gid'];
    if (gid is String) {
      final porGid = await (db.select(db.productos)..where((p) => p.globalId.equals(gid) & p.esServicio.equals(true))).getSingleOrNull();
      if (porGid != null) return porGid;
    }
    // Por nombre, sin importar mayúsculas, acentos ni espacios de más ("Corte y Barba" = "corte y barba").
    String comparable(String t) => normalizarTexto(t).trim().replaceAll(RegExp(r'\s+'), ' ');
    final nombre = comparable('${s['nombre'] ?? ''}');
    if (nombre.isEmpty) return null;
    // También uno dado de baja: el turno ya se dio y tiene que verse igual.
    final servicios = await (db.select(db.productos)..where((p) => p.esServicio.equals(true))).get();
    return servicios.where((p) => comparable(p.nombre) == nombre).firstOrNull;
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
    // Sin servicios, la app de almacén no toca lo que el bot ya tiene; Nodo Sur Servicios le manda la lista vacía (no ofrece los de ejemplo).
    if (servicios.isEmpty && !esEdicionServicios) return;
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
      cobroConLink: esEdicionServicios,
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
