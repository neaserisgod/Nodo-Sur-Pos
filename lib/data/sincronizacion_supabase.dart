// Orquesta la sincronización de las 14 tablas vía Supabase — reemplaza a
// `lib/data/sincronizacion_firestore.dart`. Con Supabase, PC y celular son
// simétricos igual que antes: los dos corren esta misma clase contra su
// propia base local, sin "cliente" y "servidor" para esto
// (`transporte_supabase.dart` es el único que sabe de Supabase; acá no se
// decide nada de merge — eso sigue siendo `repositorio_sincronizacion.dart`,
// sin tocar).
//
// Pull: dos caminos que se complementan (ver el comentario de cabecera de
// `transporte_supabase.dart`) — Realtime en vivo para la parte instantánea,
// y un pull con cursor cada [intervaloRedDeSeguridad] que es la red de seguridad
// real (cubre la sincronización inicial completa y cualquier cosa que
// Realtime se haya perdido en un corte).
// Push: igual que con Firestore, periódico, con cursor por tabla en
// `SharedPreferences`.
//
// Tráfico (2026-09-28, Supabase cortó el servicio por pasar la cuota gratis:
// 25,8 GB de egress y 9 millones de mensajes Realtime en 8 días, con una
// base de 0,03 GB): además del bucle de re-subida que ya se arregló el
// 2026-09-26 (`filtrarYaSubidas` + el trigger del servidor), el pull de las
// 14 tablas corría cada 20 s en cada dispositivo (~120.000 consultas por
// día) y CADA mensaje de Realtime volvía a pedir las 14 tablas aunque el
// mensaje ya trajera la fila. Ahora:
//   - un aviso de Realtime solo aplica la fila que trae (sin pull);
//   - una escritura local solo empuja (sin pull);
//   - el pull completo es la red de seguridad, cada [intervaloRedDeSeguridad]
//     (5 minutos) y al arrancar.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'repositorio_sincronizacion.dart';
import 'transporte_supabase.dart';

class SincronizacionSupabase {
  SincronizacionSupabase(this.db, {this.intervaloRedDeSeguridad = const Duration(minutes: 5)});

  final AppDatabase db;

  /// Cada cuánto se hace el pull completo con cursor (la red de seguridad) y
  /// se reintenta el push de lo que haya quedado sin subir. Lo instantáneo
  /// no depende de esto: Realtime entrega las filas nuevas al momento y una
  /// escritura local se empuja a los 400 ms.
  final Duration intervaloRedDeSeguridad;

  final List<SuscripcionSupabase> _subs = [];

  /// Lo que llegó por Realtime desde el último ciclo, por tabla, todavía sin
  /// aplicar a la base local — el pull con cursor ([_pullPeriodico]) también
  /// deposita acá lo que trae, así una sola función ([_aplicarPendientes])
  /// aplica todo en el orden correcto sin importar de qué camino vino.
  final Map<String, List<Map<String, dynamic>>> _pendientes = {
    for (final tabla in tablasSincronizables.keys) tabla: <Map<String, dynamic>>[],
  };

  Timer? _timer;
  Timer? _debouncePush;
  StreamSubscription<Set<TableUpdate>>? _escrituraLocalSub;
  bool _procesando = false;
  bool _pedidoDeNuevo = false;

  /// Si alguno de los pedidos acumulados mientras se procesaba necesita el
  /// pull completo (el periódico o el del arranque).
  bool _pullPedido = false;

  /// Avisa cada vez que termina un ciclo que aplicó algo de verdad — las
  /// pantallas se suscriben para refrescarse solas en vez de necesitar que
  /// la persona salga y vuelva a entrar para ver datos nuevos.
  final _cambiosAplicadosController = StreamController<void>.broadcast();
  Stream<void> get cambiosAplicados => _cambiosAplicadosController.stream;

  Future<void> iniciar() async {
    for (final tabla in tablasSincronizables.keys) {
      _subs.add(
        escucharTablaSupabase(tabla, (filas) {
          // La fila ya vino en el mensaje: se aplica sin volver a pedir las
          // 14 tablas.
          _pendientes[tabla]!.addAll(filas);
          _tick(conPull: false);
        }),
      );
    }
    _escrituraLocalSub = db.tableUpdates().listen(_onEscrituraLocal);
    _timer = Timer.periodic(intervaloRedDeSeguridad, (_) => _tick());
    await _tick();
  }

  /// Pull completo ya, sin esperar la red de seguridad — para "tirar para
  /// actualizar" en el celular.
  Future<void> sincronizarAhora() => _tick();

  void detener() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _escrituraLocalSub?.cancel();
    _debouncePush?.cancel();
    _timer?.cancel();
    _timer = null;
    _cambiosAplicadosController.close();
  }

  /// Nudge de baja latencia para una escritura LOCAL genuina (una venta, un
  /// conteo de stock, un precio editado...) — sin esto, un cambio local
  /// esperaba hasta el tick periódico antes de siquiera empezar a
  /// subirse a Supabase, aunque el otro dispositivo lo recibiera después vía
  /// Realtime casi al instante (Bruno, 2026-09-19: "buscamos
  /// instantaneidad" — el cuello de botella real ya no era el pull sino
  /// cuánto tardaba el push en arrancar). Debounced (no cada escritura
  /// dispara un tick propio: una venta con varias líneas, por ejemplo,
  /// escribe varias filas casi juntas) y sin loop: aplicar filas que trae el
  /// propio motor de sync (`_aplicarUnaFila`, `repositorio_sincronizacion.dart`)
  /// usa `customInsert`/`customUpdate` SIN `updates:` a propósito, así que
  /// eso nunca llega acá — solo una escritura hecha por código de dominio
  /// real (`db.into(...)`, `db.update(...)`) notifica.
  void _onEscrituraLocal(Set<TableUpdate> cambios) {
    if (!cambios.any((c) => tablasSincronizables.containsKey(c.table))) return;
    _debouncePush?.cancel();
    _debouncePush = Timer(const Duration(milliseconds: 400), () => _tick(conPull: false));
  }

  Future<void> _tick({bool conPull = true}) async {
    if (conPull) _pullPedido = true;
    if (_procesando) {
      _pedidoDeNuevo = true;
      return;
    }
    _procesando = true;
    try {
      var huboAlgo = false;
      do {
        _pedidoDeNuevo = false;
        if (_pullPedido) {
          _pullPedido = false;
          await _pullPeriodico();
        }
        final antesDeAplicar = _pendientes.values.any((f) => f.isNotEmpty);
        await _aplicarPendientes();
        if (antesDeAplicar) huboAlgo = true;
      } while (_pedidoDeNuevo);
      await _empujarCambiosLocales();
      await _empujarConfigCobroSiHizoFalta();
      if (huboAlgo) _cambiosAplicadosController.add(null);
    } finally {
      _procesando = false;
    }
  }

  /// Red de seguridad del pull (ver cabecera del archivo), cada
  /// [intervaloRedDeSeguridad] y al arrancar: Realtime avisa
  /// casi al instante mientras el canal esté conectado, pero no reproduce
  /// nada de lo anterior a la conexión ni lo que se pierda en un corte —
  /// este cursor por tabla (en `SharedPreferences`, separado del cursor de
  /// push) es lo que de verdad garantiza que tarde o temprano llegue todo,
  /// incluida la primera sincronización completa (cursor 0).
  ///
  /// Las 14 tablas se piden EN PARALELO (Bruno, 2026-09-18: "tarda mucho al
  /// loguear la primera vez... tiene que ser completamente instantáneo") —
  /// antes eran 14 viajes de red seguidos, uno esperando al anterior, y la
  /// primera sincronización completa (cursor 0 en las 14) pagaba esa demora
  /// entera de una sola vez. Pedirlas todas a la vez no cambia el orden en
  /// que se APLICAN después ([_aplicarPendientes] sigue respetando
  /// `tablasSincronizables` una por una, por las claves foráneas) — solo el
  /// tiempo de bajarlas.
  Future<void> _pullPeriodico() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(
      tablasSincronizables.keys.map((tabla) async {
        final clave = _clavePull(tabla);
        final cursor = prefs.getInt(clave) ?? 0;
        try {
          final resultado = await descargarCambiosSupabase(tabla, desde: cursor);
          if (resultado.filas.isEmpty) return;
          _pendientes[tabla]!.addAll(resultado.filas);
          if (resultado.cursorMaximo > cursor) {
            await prefs.setInt(clave, resultado.cursorMaximo);
          }
        } catch (e) {
          // Sin internet, Supabase caído, lo que sea — se reintenta solo en
          // el próximo tick (el cursor no avanzó).
          // ignore: avoid_print
          print('Sync Supabase: pull de $tabla falló ($e)');
        }
      }),
    );
  }

  /// Credenciales de cobro por terminal Point — solo el escritorio es
  /// autoridad de esto, la companion nunca escribe acá. Compara contra lo
  /// último empujado antes de escribir de nuevo: sin cambios, no hay nada
  /// que mandar en cada tick.
  Future<void> _empujarConfigCobroSiHizoFalta() async {
    if (!Platform.isWindows) return;
    final config = await db.select(db.configuracionTabla).getSingle();
    final prefs = await SharedPreferences.getInstance();
    final ultimoToken = prefs.getString('supabase_push_config_cobro_token');
    final ultimoTerminal = prefs.getString('supabase_push_config_cobro_terminal');
    if (config.mpAccessToken == ultimoToken && config.mpTerminalCobroId == ultimoTerminal) {
      return;
    }
    try {
      await escribirConfigCobro(
        mpAccessToken: config.mpAccessToken,
        mpTerminalCobroId: config.mpTerminalCobroId,
      );
      await _guardarOBorrar(prefs, 'supabase_push_config_cobro_token', config.mpAccessToken);
      await _guardarOBorrar(
        prefs,
        'supabase_push_config_cobro_terminal',
        config.mpTerminalCobroId,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Sync Supabase: push de configuracion/cobro falló ($e)');
    }
  }

  Future<void> _guardarOBorrar(SharedPreferences prefs, String clave, String? valor) {
    return valor == null ? prefs.remove(clave) : prefs.setString(clave, valor);
  }

  /// Aplica lo pendiente y, de paso, adelanta el cursor de PUSH de una tabla
  /// cuando lo que se acaba de recibir es más nuevo que ese cursor — sin
  /// esto, una fila que llega por pull nunca se marca como "ya la tengo" del
  /// lado del push, y el próximo [_empujarCambiosLocales] la re-sube de
  /// vuelta como si fuera un cambio local propio (el "eco" que ayudó a
  /// agotar la cuota de Firestore en un solo día de testing, 2026-09-18).
  /// Solo aplica a las tablas que comparan `actualizado_en` — las de
  /// solo-inserción usan el `id` local autoincrement como cursor de push,
  /// que no se puede anticipar antes de insertar; ese resto de eco ya era
  /// tolerado (reenviar de más algo que el otro lado ya tiene es
  /// inofensivo, tanto `aplicarCambios` como `subirFilasASupabase` son
  /// upsert por `global_id`).
  Future<void> _aplicarPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tabla in tablasSincronizables.keys) {
      final filas = _pendientes[tabla]!;
      if (filas.isEmpty) continue;
      _pendientes[tabla] = [];
      try {
        final noAplicadas = await aplicarCambios(db, tabla: tabla, filas: filas);
        if (noAplicadas.isNotEmpty) _pendientes[tabla]!.addAll(noAplicadas);
        if (tablasSincronizables[tabla]!) {
          final aplicadas = filas.where((f) => !noAplicadas.contains(f));
          if (aplicadas.isNotEmpty) {
            final maxEntrante = aplicadas
                .map((f) => (f['actualizado_en'] as num?)?.toInt() ?? 0)
                .reduce((a, b) => a > b ? a : b);
            final clave = _clavePush(tabla);
            final actual = prefs.getInt(clave) ?? 0;
            if (maxEntrante > actual) await prefs.setInt(clave, maxEntrante);
          }
        }
      } catch (_) {
        // Solo por un error real de la base (ej. se cerró a mitad de
        // camino) — vuelve toda la tanda a la cola por las dudas.
        _pendientes[tabla]!.addAll(filas);
      }
    }
  }

  /// Mismo motivo que [_pullPeriodico]: las 14 tablas se suben en paralelo,
  /// no una detrás de la otra — la lectura local (`cambiosDesde`) igual
  /// queda serializada por la única conexión de drift, pero el viaje de
  /// red a Supabase (lo que de verdad tarda) no espera al de la tabla
  /// anterior.
  ///
  /// Solo sube lo que de verdad cambió desde la última vez
  /// ([filtrarYaSubidas], `repositorio_sincronizacion.dart`): reenviar las
  /// filas del borde en cada tick fue lo que agotó la cuota de Supabase
  /// (2026-09-26) — ver el comentario de esa función.
  Future<void> _empujarCambiosLocales() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(
      tablasSincronizables.keys.map((tabla) async {
        final cursor = prefs.getInt(_clavePush(tabla)) ?? 0;
        final filas = await cambiosDesde(db, tabla: tabla, desde: cursor);
        final plan = filtrarYaSubidas(
          tabla,
          filas: filas,
          cursor: cursor,
          borde: _leerBorde(prefs, tabla),
        );
        if (plan.aSubir.isEmpty) return;
        try {
          await subirFilasASupabase(tabla, plan.aSubir);
          await prefs.setInt(_clavePush(tabla), plan.cursor);
          await prefs.setString(_claveBorde(tabla), jsonEncode(plan.borde));
        } catch (e) {
          // Sin internet, Supabase caído, lo que sea — se reintenta solo en
          // el próximo tick (el cursor no avanzó, así que las mismas filas
          // se vuelven a leer).
          // ignore: avoid_print
          print('Sync Supabase: push de $tabla falló ($e)');
        }
      }),
    );
  }

  Map<String, String> _leerBorde(SharedPreferences prefs, String tabla) {
    final crudo = prefs.getString(_claveBorde(tabla));
    if (crudo == null) return const {};
    try {
      return (jsonDecode(crudo) as Map<String, dynamic>).cast<String, String>();
    } on FormatException {
      return const {}; // peor caso: se re-sube el borde una vez
    }
  }

  String _clavePush(String tabla) => 'supabase_push_$tabla';
  String _claveBorde(String tabla) => 'supabase_push_borde_$tabla';
  String _clavePull(String tabla) => 'supabase_pull_$tabla';
}
