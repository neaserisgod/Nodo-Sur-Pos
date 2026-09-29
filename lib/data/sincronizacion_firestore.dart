// Orquesta la sincronización de las 14 tablas vía Firestore — reemplaza a
// `lib/companion/servicio_sincronizacion.dart` (HTTP celular→PC) como
// mecanismo principal. Con Firestore, PC y celular son simétricos: los dos
// corren esta misma clase contra su propia base local, sin más "cliente" y
// "servidor" para esto (`transporte_firestore.dart` es el único que sabe de
// Firestore; acá no se decide NADA de merge — eso sigue siendo
// `repositorio_sincronizacion.dart`, sin tocar).
//
// Pull: en vivo, por listener de Firestore (`escucharTablaFirestore`) — un
// cambio en cualquiera de los dos dispositivos llega casi al instante al
// otro, apenas los dos tengan internet.
// Push: periódico (cada [intervaloEmpuje]), no atado a cada escritura —
// enganchar esto a cada una de las decenas de funciones de
// `lib/data/repositorio_*.dart` que insertan una fila es un cambio de
// arquitectura más grande, fuera de esta entrega. El pull en vivo ya cubre
// la mitad más importante: enterarse de lo que cambió el OTRO dispositivo
// sin tener que pedirlo.
import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'repositorio_sincronizacion.dart';
import 'transporte_firestore.dart';

class SincronizacionFirestore {
  SincronizacionFirestore(this.db, {this.intervaloEmpuje = const Duration(seconds: 20)});

  final AppDatabase db;
  final Duration intervaloEmpuje;

  final List<SuscripcionFirestore> _subs = [];

  /// Lo que llegó de Firestore desde el último ciclo, por tabla, todavía sin
  /// aplicar a la base local. Los listeners de las 14 tablas son 14
  /// colecciones independientes — pueden avisar en cualquier orden entre
  /// sí, así que juntar acá y aplicar después en el orden de
  /// [tablasSincronizables] es lo que evita una violación de clave foránea
  /// (ej. que `lineas_de_venta` avise antes que su `ventas`).
  final Map<String, List<Map<String, dynamic>>> _pendientes = {
    for (final tabla in tablasSincronizables.keys) tabla: <Map<String, dynamic>>[],
  };

  Timer? _timer;
  bool _procesando = false;

  /// true si algo pidió un ciclo mientras uno ya estaba corriendo — sin
  /// esto, un cambio que llega a mitad de un `_tick()` en curso (Bruno,
  /// 2026-09-18: "tarda en sincronizar... tengo que entrar y volver a
  /// salir") se quedaba esperando hasta el próximo tick DEL TIMER (hasta
  /// [intervaloEmpuje] de más), en vez de procesarse apenas termina el que
  /// ya estaba en curso.
  bool _pedidoDeNuevo = false;

  /// Avisa cada vez que termina un ciclo que aplicó algo de verdad — las
  /// pantallas se suscriben para refrescarse solas (Bruno: "no hay nada que
  /// actualice la app cuando se sincronizó") en vez de necesitar que la
  /// persona salga y vuelva a entrar para ver datos nuevos.
  final _cambiosAplicadosController = StreamController<void>.broadcast();
  Stream<void> get cambiosAplicados => _cambiosAplicadosController.stream;

  /// Arranca los 14 listeners y el primer ciclo de aplicar/empujar — de ahí
  /// en más, [_tick] se repite cada [intervaloEmpuje] Y cada vez que
  /// cualquiera de los 14 listeners avisa algo nuevo (no solo por el
  /// timer): antes, un cambio que llegaba de Firestore se quedaba en
  /// [_pendientes] sin aplicarse a la base local hasta el próximo tick
  /// periódico — hasta [intervaloEmpuje] de demora de más, encima de la
  /// demora real de red.
  Future<void> iniciar() async {
    for (final tabla in tablasSincronizables.keys) {
      _subs.add(
        escucharTablaFirestore(tabla, (filas) {
          _pendientes[tabla]!.addAll(filas);
          _tick();
        }),
      );
    }
    _timer = Timer.periodic(intervaloEmpuje, (_) => _tick());
    await _tick();
  }

  void detener() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _timer?.cancel();
    _timer = null;
    _cambiosAplicadosController.close();
  }

  Future<void> _tick() async {
    if (_procesando) {
      // Ya hay un ciclo corriendo (puede haber arrancado por el timer o por
      // otro listener) — no se corre uno encima del otro, pero se marca
      // para repetir apenas termine, así lo que acaba de llegar no espera
      // al próximo tick del timer.
      _pedidoDeNuevo = true;
      return;
    }
    _procesando = true;
    try {
      var huboAlgo = false;
      do {
        _pedidoDeNuevo = false;
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

  /// Credenciales de cobro por terminal Point (Bruno, 2026-09-18: "quiero
  /// que ande sin la PC") — solo el escritorio es autoridad de esto, la
  /// companion nunca escribe acá (`leerConfigCobro` en
  /// `transporte_firestore.dart` es de solo lectura). Compara contra lo
  /// último empujado antes de escribir de nuevo: sin cambios, no hay nada
  /// que mandar en cada tick de 20s.
  Future<void> _empujarConfigCobroSiHizoFalta() async {
    if (!Platform.isWindows) return;
    final config = await db.select(db.configuracionTabla).getSingle();
    final prefs = await SharedPreferences.getInstance();
    final ultimoToken = prefs.getString('firestore_push_config_cobro_token');
    final ultimoTerminal = prefs.getString('firestore_push_config_cobro_terminal');
    if (config.mpAccessToken == ultimoToken && config.mpTerminalCobroId == ultimoTerminal) {
      return;
    }
    try {
      await escribirConfigCobro(
        mpAccessToken: config.mpAccessToken,
        mpTerminalCobroId: config.mpTerminalCobroId,
      );
      await _guardarOBorrar(prefs, 'firestore_push_config_cobro_token', config.mpAccessToken);
      await _guardarOBorrar(
        prefs,
        'firestore_push_config_cobro_terminal',
        config.mpTerminalCobroId,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Sync Firestore: push de configuracion/cobro falló ($e)');
    }
  }

  Future<void> _guardarOBorrar(SharedPreferences prefs, String clave, String? valor) {
    return valor == null ? prefs.remove(clave) : prefs.setString(clave, valor);
  }

  Future<void> _aplicarPendientes() async {
    for (final tabla in tablasSincronizables.keys) {
      final filas = _pendientes[tabla]!;
      if (filas.isEmpty) continue;
      _pendientes[tabla] = [];
      try {
        // `aplicarCambios` ya no lanza por una fila puntual fuera de orden
        // (su padre todavía no llegó, ej. un producto cuya categoría está en
        // la tanda de otra tabla que todavía no se aplicó este mismo ciclo,
        // o ni siquiera llegó de Firestore todavía) — devuelve esas filas
        // sin aplicar en vez de tirar toda la tanda, así una sola fila
        // trabada no bloquea al resto de filas de la misma tabla que sí
        // podían aplicarse ya (Bruno, 2026-09-18: "no veo productos... ni
        // suelto, ni leche" — antes SÍ bloqueaba, esta fue la causa real).
        // Las que quedaron sin aplicar vuelven a la cola para el próximo
        // tick; `aplicarCambios` es idempotente (upsert por `global_id`),
        // así que reintentar de más nunca duplica nada.
        final noAplicadas = await aplicarCambios(db, tabla: tabla, filas: filas);
        if (noAplicadas.isNotEmpty) _pendientes[tabla]!.addAll(noAplicadas);
        // Ya NO se adelanta acá el cursor de push con el cursor de lo
        // recibido (se probó y se sacó, 2026-09-18): una fila local vieja
        // que todavía no se empujó nunca puede tener un cursor más bajo que
        // lo que acaba de llegar de otro dispositivo (por ejemplo,
        // `actualizado_en` NULL en una fila histórica de antes de que
        // existiera esa columna) — adelantar el cursor la excluye de
        // cualquier empuje futuro para siempre, un bug real que dejó 11 de
        // 13 categorías de Bruno sin sincronizar. El costo de no adelantarlo
        // es reenviar de vuelta, alguna vez, lo que ya se recibió — inofensivo
        // porque `subirFilasAFirestore` escribe por `global_id` (upsert).
      } catch (_) {
        // Esto ya no debería pasar por una fila fuera de orden (ver arriba)
        // — solo por un error real de la base (ej. se cerró a mitad de
        // camino). Vuelve toda la tanda a la cola por las dudas.
        _pendientes[tabla]!.addAll(filas);
      }
    }
  }

  Future<void> _empujarCambiosLocales() async {
    final prefs = await SharedPreferences.getInstance();
    for (final tabla in tablasSincronizables.keys) {
      final cursor = prefs.getInt(_clavePush(tabla)) ?? 0;
      final filas = await cambiosDesde(db, tabla: tabla, desde: cursor);
      if (filas.isEmpty) continue;
      try {
        await subirFilasAFirestore(tabla, filas);
        await prefs.setInt(_clavePush(tabla), cursorMaximo(tabla, filas));
      } catch (e) {
        // Sin internet, Firestore caído, lo que sea — se reintenta solo en
        // el próximo tick (el cursor no avanzó, así que las mismas filas
        // se vuelven a leer).
        // ignore: avoid_print
        print('Sync Firestore: push de $tabla falló ($e)');
      }
    }
  }

  String _clavePush(String tabla) => 'firestore_push_$tabla';
}
