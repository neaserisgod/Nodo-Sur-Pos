// Prueba (El dueño, 2026-10-10): el bot de WhatsApp adentro de la app, sin Termux.
//
// Corre el Node que Termux compila para Android, empaquetado en el APK como `libns_node.so` (lo arma
// `tool/preparar_bot_android.sh`). Android solo deja ejecutar lo que quedó en la carpeta de librerías de la app, que desde Dart
// se encuentra mirando dónde se cargó `libflutter.so` (`/proc/self/maps`). El JavaScript (Baileys y el script de prueba) viene
// en `assets/bot/bot.zip` y se descomprime en la carpeta de la app. Solo corre ese script, con argumentos fijos: no baja ni
// ejecuta código de afuera.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class BotEnCelular {
  Process? _proceso;
  final _lineas = StreamController<String>.broadcast();

  Stream<String> get lineas => _lineas.stream;
  bool get andando => _proceso != null;

  /// Arranca la prueba. [numero] (opcional): pide el código para vincular ese WhatsApp. Devuelve null si arrancó, o qué falta.
  Future<String?> iniciar({String? numero}) async {
    if (_proceso != null) return 'Ya está andando';
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
    final args = [p.join(dir.path, 'prueba.js'), p.join(soporte.path, 'bot-datos')];
    final digitos = (numero ?? '').replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty) args.add(digitos);
    _lineas.add('Node: ${node.path} (${node.lengthSync() ~/ 1048576} MB)');
    try {
      final proc = await Process.start(
        node.path,
        args,
        workingDirectory: dir.path,
        environment: {'LD_LIBRARY_PATH': libs, 'HOME': soporte.path, 'TMPDIR': (await getTemporaryDirectory()).path},
      );
      _proceso = proc;
      for (final s in [proc.stdout, proc.stderr]) {
        s.transform(utf8.decoder).transform(const LineSplitter()).listen(_lineas.add);
      }
      unawaited(proc.exitCode.then((c) {
        _lineas.add('— Node terminó (código $c)');
        _proceso = null;
      }));
      return null;
    } catch (e) {
      return 'Node no arrancó: $e';
    }
  }

  void detener() => _proceso?.kill();

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
