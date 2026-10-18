// Los pedidos del bot de WhatsApp en la lista de un local gastronómico (Nodo Gastro, `REGLAS-NEGOCIO.md` §22,
// `docs/PLAN-GASTRONOMIA.md` etapa 5). Lo corre el equipo que sube la sync a la nube, al terminar cada vuelta (como los turnos del
// bot, `turnos_bot_nube.dart`): uno solo a la vez, así un pedido del bot no entra dos veces a la lista.
//
// Tres cosas por vuelta:
//  1. BAJAR los pedidos que tomó el bot (`/api/bot/pedidos`, con cursor) y ponerlos en la lista: "por confirmar", o "por hacer"
//     si el local dejó que entren solos.
//  2. AVISAR lo que el local hizo con cada uno (aceptarlo, rechazarlo, listo, salió, entregado, cancelado): el bot le escribe al
//     cliente.
//  3. LLEVAR al bot cómo trabaja el local (entregas, zonas, pago, cocina, horario), solo cuando algo de eso cambió. Cambiar la
//     cocina a "pausada" llega en la vuelta que sigue a ese cambio.
//
// Nunca tira: un error se ve en la próxima vuelta, y la lista funciona igual sin el bot.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_configuracion.dart' show modulosNegocioActuales;
import '../data/repositorio_pedidos_gastronomia.dart';
import '../data/repositorio_turnos.dart' show configAgendaActual;
import '../domain/bot_whatsapp.dart';
import '../domain/forma_de_trabajo.dart';
import '../edicion.dart' show esEdicionGastronomia;
import 'avisos_bot.dart';
import 'cuenta_nube.dart';
import 'registro_errores.dart' show registrarSiNoEsDeRed;

const _claveCursor = 'pedidosBot.cursor';
const _claveEnviados = 'pedidosBot.enviados';

/// Los pedidos del bot que bajaron pero no se pudieron poner en la lista, con el motivo: la pantalla de Pedidos los muestra y se
/// reintentan solos en cada vuelta (mismo criterio que `turnosBotSinCargar`).
final ValueNotifier<List<String>> pedidosBotSinCargar = ValueNotifier(const []);

class SincronizadorPedidosBot {
  SincronizadorPedidosBot({required this.db, required this.cliente, this.alBajar}) {
    _aviso = avisosPedidoBot.listen((_) {
      final token = _ultimoToken;
      if (token != null) unawaited(vuelta(token));
    });
  }

  final AppDatabase db;
  final ClienteNube cliente;

  /// Se llama cuando bajó al menos un pedido nuevo: la lista abierta se redibuja al toque.
  final void Function()? alBajar;

  StreamSubscription<int>? _aviso;
  static const revisarPlanCada = Duration(hours: 1);
  EstadoBot? _estado;
  DateTime? _planRevisado;
  String? _ultimaConfig;
  String? _ultimoToken;
  Future<void>? _enCurso;
  var _repetir = false;

  void cerrar() => _aviso?.cancel();

  /// Una vuelta entera. Si ya hay una corriendo, al terminar esa se hace otra (un pedido que llega en el medio no espera a la
  /// próxima vuelta de la sync).
  Future<void> vuelta(String token) {
    _ultimoToken = token;
    final enCurso = _enCurso;
    if (enCurso != null) {
      _repetir = true;
      return enCurso;
    }
    return _enCurso = _correr();
  }

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
      // Nodo Gastro es de gastronomía aunque el rubro guardado no lo diga (el dueño salteó el alta con "Después"): sin esto, los
      // pedidos del bot nunca llegaban a la lista.
      if (!esEdicionGastronomia && (await modulosNegocioActuales(db)).forma != FormaDeTrabajo.gastronomia) return;
      final ahora = DateTime.now();
      if (_estado == null || _planRevisado == null || ahora.difference(_planRevisado!) >= revisarPlanCada) {
        _estado = await cliente.estadoBot(token);
        _planRevisado = ahora;
      }
      if (_estado?.tieneBot != true) return;
      final prefs = await SharedPreferences.getInstance();
      await _bajar(token, prefs);
      await _avisar(token, prefs);
      if (_estado!.puedeConfigurar) await _publicarConfig(token);
    } catch (e, st) {
      unawaited(registrarSiNoEsDeRed('Pedidos del bot', e, st));
    }
  }

  Future<void> _bajar(String token, SharedPreferences prefs) async {
    var desde = prefs.getInt(_claveCursor) ?? 0;
    final usuario = await (db.select(db.usuarios)..limit(1)).getSingleOrNull();
    final motivos = <String>[];
    int? primeroQueFallo;
    var bajoAlgo = false;
    while (true) {
      final r = await cliente.pedidosBot(token, desde: desde);
      for (final p in r.pedidos) {
        // Solo se pone lo que el local tiene que atender: uno que el bot ya mandó resuelto (otro equipo lo aceptó) ya está.
        if (p.estado != EstadoPedidoBot.porConfirmar) continue;
        try {
          if (usuario == null) throw const PedidoIncompleto('Falta elegir usuario en este equipo.');
          final antes = await (db.select(db.pedidosGastronomia)..where((x) => x.idRemoto.equals('${p.id}'))).getSingleOrNull();
          await importarPedidoDelBot(db, p, usuarioId: usuario.id);
          if (antes == null) bajoAlgo = true;
        } on PedidoIncompleto catch (e) {
          motivos.add(e.mensaje);
          if (primeroQueFallo == null || p.actualizado < primeroQueFallo) primeroQueFallo = p.actualizado;
        }
      }
      if (!r.mas || r.hasta <= desde) {
        desde = r.hasta;
        break;
      }
      desde = r.hasta;
    }
    // Lo que no se pudo poner se vuelve a pedir la próxima vez (por eso el cursor no lo pasa de largo).
    await prefs.setInt(_claveCursor, primeroQueFallo == null ? desde : primeroQueFallo - 1);
    if (!_mismaLista(motivos, pedidosBotSinCargar.value)) pedidosBotSinCargar.value = motivos;
    if (bajoAlgo) alBajar?.call();
  }

  Future<void> _avisar(String token, SharedPreferences prefs) async {
    final enviados = _leerEnviados(prefs);
    for (final (p, estado) in await pedidosDelBotParaAvisar(db, enviados)) {
      final idRemoto = p.idRemoto!;
      final id = int.tryParse(idRemoto);
      if (id == null) continue;
      final antes = enviados[idRemoto];
      try {
        if (estado == 'aceptado' || estado == 'rechazado') {
          await cliente.resolverPedidoBot(token, id, aceptado: estado == 'aceptado');
        } else if (estado == 'cancelado' && antes == null) {
          // Se canceló sin haberlo aceptado nunca: para el sitio es un rechazo.
          await cliente.resolverPedidoBot(token, id, aceptado: false);
        } else {
          // En el sitio todavía está "por confirmar" (se aceptó y se hizo antes de una vuelta): primero se acepta.
          if (antes == null) await cliente.resolverPedidoBot(token, id, aceptado: true);
          await cliente.avanzarPedidoBot(token, id, estado);
        }
        enviados[idRemoto] = estado;
      } on ErrorNube catch (e) {
        // Ya estaba así o más adelante (otro equipo lo avisó), o el sitio ya no lo tiene: no hay nada más que avisar.
        if (e.codigo == 'ya_resuelto' || e.codigo == 'paso_invalido' || e.codigo == 'no_existe') {
          enviados[idRemoto] = estado;
        } else {
          rethrow;
        }
      } finally {
        await prefs.setString(_claveEnviados, jsonEncode(enviados));
      }
    }
  }

  Map<String, String> _leerEnviados(SharedPreferences prefs) {
    try {
      return (jsonDecode(prefs.getString(_claveEnviados) ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _publicarConfig(String token) async {
    final config = await configPedidosActual(db);
    final cocina = await estadoCocinaActual(db);
    final agenda = await configAgendaActual(db);
    final entrada = jsonEncode([config.toJson(), cocina.clave, agenda.horario.toJson(), agenda.aliasSena, agenda.titularSena]);
    if (entrada == _ultimaConfig) return;
    final actual = await cliente.configBot(token);
    // Sin la configuración básica (los números) el bot no puede arrancar: eso se carga una vez en Más › Bot de WhatsApp.
    final anterior = actual.config;
    if (anterior == null) return;
    final nueva = configBotConPedidos(
      anterior,
      config: config,
      cocina: cocina,
      horario: agenda.horario,
      alias: agenda.aliasSena,
      titular: agenda.titularSena,
    );
    if (jsonEncode(nueva) != jsonEncode(anterior)) await cliente.guardarConfigBot(token, nueva);
    _ultimaConfig = entrada;
  }

  static bool _mismaLista(List<String> a, List<String> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
}
