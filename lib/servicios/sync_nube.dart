// Sincronización entre dispositivos a través de la nube de Nodo Sur: la PC (y
// después los celulares) suben sus cambios como lotes y bajan los de los
// demás. Cada cambio local dispara una vuelta; además hay un latido para
// enterarse de lo que subieron otros (El dueño, 2026-10-01: "cada modificación
// lanza una sync"; "si apago la PC el sistema tiene que seguir funcionando").
//
// Nunca tira una excepción hacia quien llama: una vuelta fallida es un
// resultado con texto, y la caja sigue como si nada. Sin internet no se
// pierde nada — lo que no subió se vuelve a calcular desde la base en la
// próxima vuelta.
//
// Primero BAJA y después SUBE: un dispositivo que vuelve de estar apagado
// aplica antes lo que se perdió, y lo suyo llega último (y gana) en vez de
// pisar a ciegas lo que otro hizo mientras tanto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/registro_sync_nube.dart';
import 'cuenta_nube.dart';

/// Dónde se guarda el registro de la sync. Fuera de la base, junto al token de
/// la cuenta: restaurar una copia no tiene que dejar un registro que diga que
/// filas que ya no están "ya se subieron".
abstract class AlmacenEstadoSync {
  Future<EstadoSyncNube> leer();
  Future<void> guardar(EstadoSyncNube estado);
  Future<void> borrar();
}

class AlmacenEstadoSyncEnMemoria implements AlmacenEstadoSync {
  Map<String, dynamic>? _json;

  @override
  Future<EstadoSyncNube> leer() async => EstadoSyncNube.desdeJson(_json);

  @override
  Future<void> guardar(EstadoSyncNube estado) async => _json = jsonDecode(jsonEncode(estado.toJson())) as Map<String, dynamic>;

  @override
  Future<void> borrar() async => _json = null;
}

class AlmacenEstadoSyncEnArchivo implements AlmacenEstadoSync {
  AlmacenEstadoSyncEnArchivo(this.carpeta);
  final String carpeta;

  File get _archivo => File(p.join(carpeta, 'nodosur_sync.json'));

  @override
  Future<EstadoSyncNube> leer() async {
    try {
      return EstadoSyncNube.desdeJson(jsonDecode(await _archivo.readAsString()));
    } catch (_) {
      return EstadoSyncNube();
    }
  }

  @override
  Future<void> guardar(EstadoSyncNube estado) async {
    await Directory(carpeta).create(recursive: true);
    // Temporal + renombrar: un corte a mitad de camino no deja el registro a medias.
    final tmp = File('${_archivo.path}.tmp');
    await tmp.writeAsString(jsonEncode(estado.toJson()), flush: true);
    await tmp.rename(_archivo.path);
  }

  @override
  Future<void> borrar() async {
    try {
      await _archivo.delete();
    } catch (_) {}
  }
}

sealed class ResultadoSyncNube {
  const ResultadoSyncNube();
}

class SyncNubeOk extends ResultadoSyncNube {
  const SyncNubeOk({required this.bajadas, required this.subidas});

  /// Filas aplicadas que venían de otros dispositivos.
  final int bajadas;

  /// Filas propias que se mandaron.
  final int subidas;
}

class SyncNubeSinCuenta extends ResultadoSyncNube {
  const SyncNubeSinCuenta();
}

/// El servidor ya no guarda lo que este dispositivo se perdió: hay que ponerse
/// al día desde una copia de seguridad.
class SyncNubeExpirada extends ResultadoSyncNube {
  const SyncNubeExpirada();
}

class SyncNubeFallida extends ResultadoSyncNube {
  const SyncNubeFallida(this.mensaje, {this.pideVincular = false, this.sinRed = false});
  final String mensaje;
  final bool pideVincular;

  /// No hay conexión (no es un error de la cuenta): se reintenta sola.
  final bool sinRed;
}

class ServicioSyncNube {
  ServicioSyncNube({
    required this.db,
    required this.almacenCuenta,
    required this.cliente,
    required this.almacenEstado,
    this.alAplicarBajada,
  });

  final AppDatabase db;
  final AlmacenCuenta almacenCuenta;
  final ClienteNube cliente;
  final AlmacenEstadoSync almacenEstado;

  /// Se llama cuando se aplicó algo que vino de otro dispositivo, para que las pantallas se refresquen.
  final void Function()? alAplicarBajada;

  /// Último resultado: lo que muestra la pantalla de dispositivos ("sin conexión", "al día").
  ResultadoSyncNube? ultimo;

  bool _enCurso = false;
  bool _otraVez = false;
  StreamSubscription<void>? _cambios;
  Timer? _latido;

  /// Una vuelta completa (bajar, subir). Si ya hay una corriendo, anota que hace falta otra al terminar.
  Future<ResultadoSyncNube> sincronizar() async {
    if (_enCurso) {
      _otraVez = true;
      return ultimo ?? const SyncNubeOk(bajadas: 0, subidas: 0);
    }
    _enCurso = true;
    try {
      ResultadoSyncNube r;
      do {
        _otraVez = false;
        r = await _unaVuelta();
      } while (_otraVez && r is SyncNubeOk);
      return ultimo = r;
    } finally {
      _enCurso = false;
    }
  }

  Future<ResultadoSyncNube> _unaVuelta() async {
    final cuenta = await almacenCuenta.leer();
    if (cuenta == null) return const SyncNubeSinCuenta();
    try {
      final estado = await almacenEstado.leer();
      final bajadas = await _bajar(cuenta.token, estado);
      if (estado.necesitaCopia) return const SyncNubeExpirada();
      final subidas = await _subir(cuenta.token, estado);
      if (bajadas > 0) alAplicarBajada?.call();
      return SyncNubeOk(bajadas: bajadas, subidas: subidas);
    } on ErrorNube catch (e) {
      return SyncNubeFallida(e.mensaje, pideVincular: e.pideVincularDeNuevo, sinRed: e.codigo == 'sin_red');
    } catch (e) {
      return SyncNubeFallida('No se pudo sincronizar: $e');
    }
  }

  Future<int> _bajar(String token, EstadoSyncNube estado) async {
    var aplicadas = 0;
    var mas = true;
    while (mas) {
      final antes = estado.cursorBajada;
      final r = await cliente.bajarLotes(token, desde: antes);
      if (r.expirada) {
        estado.necesitaCopia = true;
        await almacenEstado.guardar(estado);
        return aplicadas;
      }
      aplicadas += await aplicarLotesBajados(db, estado, [
        for (final l in r.lotes) LoteBajado(seq: l.seq, deviceId: l.deviceId, creadoEn: l.creadoEn, bytes: l.bytes),
      ]);
      if (r.hasta > estado.cursorBajada) estado.cursorBajada = r.hasta;
      await almacenEstado.guardar(estado);
      // Una página puede traer solo lotes propios (no se devuelven) y aun así haber más: se sigue con el cursor
      // nuevo. Si el cursor no avanzó no hay nada que seguir pidiendo.
      mas = r.mas && estado.cursorBajada > antes;
    }
    return aplicadas;
  }

  Future<int> _subir(String token, EstadoSyncNube estado) async {
    final plan = await prepararSubidas(db, estado);
    avanzarSinSubir(estado, plan);
    var subidas = 0;
    try {
      for (final lote in plan.lotes) {
        await cliente.subirLote(token, loteId: lote.id, bytes: lote.bytes, sha256: lote.sha256);
        confirmarSubida(estado, plan, lote);
        subidas += lote.entradas.length;
        await almacenEstado.guardar(estado); // por lote: un corte a la mitad no repite lo que ya llegó
      }
    } finally {
      await almacenEstado.guardar(estado);
    }
    return subidas;
  }

  /// Arranca la sync automática: una vuelta con cada aviso de [cambiosLocales] (ya agrupado por quien lo emite)
  /// y un latido cada [latido] para enterarse de lo que subieron los demás.
  void iniciar({required Stream<void> cambiosLocales, Duration latido = const Duration(seconds: 20)}) {
    detener();
    _cambios = cambiosLocales.listen((_) => unawaited(sincronizar()));
    _latido = Timer.periodic(latido, (_) => unawaited(sincronizar()));
    unawaited(sincronizar());
  }

  void detener() {
    _cambios?.cancel();
    _latido?.cancel();
    _cambios = null;
    _latido = null;
  }

  /// Olvida el registro: la próxima vuelta baja todo desde el principio. Para después de restaurar una copia.
  Future<void> reiniciar() => almacenEstado.borrar();
}
