// Prueba (El dueño, 2026-10-10): el bot de WhatsApp adentro de la app, sin Termux.
//
// Corre el Node que Termux compila para Android, empaquetado en el APK como `libns_node.so` (lo arma
// `tool/preparar_bot_android.sh`). Android solo deja ejecutar lo que quedó en la carpeta de librerías de la app, que desde Dart
// se encuentra mirando dónde se cargó `libflutter.so` (`/proc/self/maps`). El JavaScript (Baileys y el script de prueba) viene
// en `assets/bot/bot.zip` y se descomprime en la carpeta de la app. Solo corre ese script, con argumentos fijos: no baja ni
// ejecuta código de afuera.
//
// Node se lanza suelto (no atado a esta pantalla ni a Dart): si se cierra la pantalla o la app pasa a segundo plano, sigue. Lo que
// lo mantiene vivo es `ServicioBot.kt` (servicio en primer plano con notificación fija y wakelock). Lo que escribe va a
// `bot-datos/bot.log`, que esta clase lee; el pid queda en `bot-datos/bot.pid` para retomarlo al volver a abrir la pantalla.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _canal = MethodChannel('nodosur/bot');

/// La carpeta donde Android dejó las librerías de la app (la de `libflutter.so`). Null si no se encuentra.
Future<String?> carpetaLibrerias() async {
  try {
    for (final linea in await File('/proc/self/maps').readAsLines()) {
      final i = linea.indexOf('/libflutter.so');
      if (i < 0) continue;
      final ruta = linea.substring(linea.indexOf('/'), i);
      if (!ruta.contains('!')) return ruta; // dentro del APK sin descomprimir no sirve
    }
  } catch (_) {}
  return null;
}

/// Si ese pid es nuestro Node (y no otro proceso que reusó el número).
bool _esNode(int pid) {
  try {
    return File('/proc/$pid/cmdline').readAsStringSync().contains('libns_node');
  } catch (_) {
    return false;
  }
}

class BotEnCelular {
  final _lineas = StreamController<String>.broadcast();
  Timer? _lector;
  int _leido = 0;
  String _resto = '';
  int? _pid;

  Stream<String> get lineas => _lineas.stream;
  bool get andando => _pid != null && _esNode(_pid!);

  Future<Directory> _datos() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'bot-datos'));

  /// Si ya hay un bot andando de antes (se cerró la pantalla y se volvió a abrir), lo retoma: muestra el registro desde el
  /// principio y sigue leyendo. Devuelve si lo encontró.
  Future<bool> retomar() async {
    final datos = await _datos();
    final archivoPid = File(p.join(datos.path, 'bot.pid'));
    if (!archivoPid.existsSync()) return false;
    final pid = int.tryParse(archivoPid.readAsStringSync().trim());
    if (pid == null || !_esNode(pid)) return false;
    _pid = pid;
    _leerDesde(File(p.join(datos.path, 'bot.log')), 0);
    return true;
  }

  /// Arranca la prueba. [numero] (opcional): pide el código para vincular ese WhatsApp. Devuelve null si arrancó, o qué falta.
  Future<String?> iniciar({String? numero}) async {
    if (andando) return 'Ya está andando';
    final libs = await carpetaLibrerias();
    if (libs == null) return 'No encontré la carpeta de librerías de la app';
    final node = File(p.join(libs, 'libns_node.so'));
    if (!node.existsSync()) return 'Esta versión de la app no trae Node (falta libns_node.so en $libs)';
    final soporte = await getApplicationSupportDirectory();
    final dir = Directory(p.join(soporte.path, 'bot'));
    try {
      await _descomprimir(dir);
    } catch (e) {
      return 'No pude preparar el JavaScript del bot: $e';
    }
    final datos = await _datos();
    datos.createSync(recursive: true);
    final log = File(p.join(datos.path, 'bot.log'))..writeAsStringSync('Node: ${node.path} (${node.lengthSync() ~/ 1048576} MB)\n');
    final args = [p.join(dir.path, 'prueba.js'), datos.path];
    final digitos = (numero ?? '').replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty) args.add(digitos);
    try {
      final proc = await Process.start(
        node.path,
        args,
        workingDirectory: dir.path,
        environment: {'LD_LIBRARY_PATH': libs, 'HOME': soporte.path, 'TMPDIR': (await getTemporaryDirectory()).path},
        mode: ProcessStartMode.detached,
      );
      _pid = proc.pid;
      File(p.join(datos.path, 'bot.pid')).writeAsStringSync('${proc.pid}');
    } catch (e) {
      return 'Node no arrancó: $e';
    }
    try {
      await _canal.invokeMethod('mantener', {'pid': _pid});
    } catch (e) {
      _lineas.add('ERROR no pude dejar el servicio en primer plano: $e (el bot anda, pero Android puede cerrarlo)');
    }
    _leerDesde(log, 0);
    return null;
  }

  Future<void> detener() async {
    final pid = _pid;
    if (pid != null && _esNode(pid)) Process.killPid(pid);
    _pid = null;
    try {
      await _canal.invokeMethod('soltar');
    } catch (_) {}
    try {
      File(p.join((await _datos()).path, 'bot.pid')).deleteSync();
    } catch (_) {}
  }

  /// Si Android ya deja correr la app sin el ahorro de batería (que en muchas marcas congela las apps con la pantalla apagada).
  Future<bool> sinRestriccionesDeBateria() async {
    try {
      return await _canal.invokeMethod<bool>('sinRestricciones') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> pedirSinRestriccionesDeBateria() async {
    try {
      await _canal.invokeMethod('pedirSinRestricciones');
    } catch (_) {}
  }

  /// Deja de leer el registro (la pantalla se cerró). El bot sigue andando.
  void soltarPantalla() {
    _lector?.cancel();
    _lector = null;
  }

  // Lee lo nuevo del registro cada segundo. Cuando Node termina, lo avisa una vez y para.
  void _leerDesde(File log, int desde) {
    _lector?.cancel();
    _leido = desde;
    _resto = '';
    void leer() {
      try {
        final largo = log.existsSync() ? log.lengthSync() : 0;
        if (largo > _leido) {
          final f = log.openSync();
          f.setPositionSync(_leido);
          final bytes = f.readSync(largo - _leido);
          f.closeSync();
          _leido = largo;
          final texto = _resto + utf8.decode(bytes, allowMalformed: true);
          final partes = texto.split('\n');
          _resto = partes.removeLast();
          partes.where((l) => l.isNotEmpty).forEach(_lineas.add);
        }
      } catch (_) {}
      if (_pid != null && !_esNode(_pid!)) {
        _lineas.add('— Node terminó');
        _pid = null;
        _lector?.cancel();
        _canal.invokeMethod('soltar').catchError((_) => null);
      }
    }

    leer();
    _lector = Timer.periodic(const Duration(seconds: 1), (_) => leer());
  }

  /// Descomprime `assets/bot/bot.zip` si cambió desde la última vez (por su tamaño, que cambia con cada versión del bot).
  Future<void> _descomprimir(Directory dir) async {
    final datos = await rootBundle.load('assets/bot/bot.zip');
    final marca = File(p.join(dir.path, '.version'));
    final version = '${datos.lengthInBytes}';
    if (marca.existsSync() && marca.readAsStringSync() == version) return;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final zip = ZipDecoder().decodeBytes(datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes));
    for (final f in zip.files) {
      final destino = p.normalize(p.join(dir.path, f.name));
      if (!p.isWithin(dir.path, destino)) continue;
      if (f.isFile) {
        File(destino)
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.content as List<int>);
      } else {
        Directory(destino).createSync(recursive: true);
      }
    }
    marca.writeAsStringSync(version);
  }
}
