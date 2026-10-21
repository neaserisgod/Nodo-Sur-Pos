// El bot de WhatsApp adentro de Nodo Sur Servicios, sin Termux (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`).
//
// Corre el Node que Termux compila para Android, empaquetado en el APK como `libns_node.so`, con el bot de verdad (repo botdemo)
// que viene en `assets/bot/bot.zip` (los arma `tool/preparar_bot_android.sh`). Lo que hace esta clase:
//  * descomprime el bot en una carpeta por versión (`bot/<huella>`): al actualizar la app, el Node que corre sigue con la suya
//    hasta que Android lo reinicia con la nueva, sin que se le cambien los archivos abajo;
//  * le consigue al bot su token de Nodo Sur (`nodosur.json`) con la cuenta vinculada de este celular, sin navegador;
//  * le pide a Android que lo encienda o lo apague (`ServicioBot.kt`, que lo mantiene vivo, lo levanta si se cae y lo enciende
//    al prender el celular).
// Los datos del bot (sesión de WhatsApp, su base, el estado) van aparte, en `bot-datos/`, y no se tocan al actualizar.
//
// En Windows (Nodo Sur Servicios de escritorio, 2026-10-15) es lo mismo con otro [MotorBot]: `bot_en_pc.dart`.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/bot_en_celular.dart';
import 'acceso_bot.dart';

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

/// Quién mantiene a Node corriendo en este equipo: el servicio de Android ([MotorBotAndroid]) o el supervisor de Windows
/// (`MotorBotWindows`, `bot_en_pc.dart`). El resto (descomprimir, la cuenta, el estado) es igual en los dos.
abstract class MotorBot {
  Future<bool> encendido();
  Future<void> encender({required String codigo, required String datos, required String numero});
  Future<void> apagar();

  /// Qué le falta a esta instalación para correr el bot (null si nada).
  Future<String?> faltante();

  /// Archivos que van al lado del bot en su carpeta (en Windows: Node y el supervisor), por nombre.
  Future<Map<String, File>> extras() async => const {};

  /// Cuánto esperar después de [apagar] para que Node termine de verdad.
  Duration get esperaAlApagar => const Duration(seconds: 2);

  Future<bool> sinRestriccionesDeBateria() async => true;
  Future<void> pedirSinRestriccionesDeBateria() async {}
}

/// Android: `ServicioBot.kt` por el canal `nodosur/bot`. Node viene en el APK como `libns_node.so`.
class MotorBotAndroid extends MotorBot {
  MotorBotAndroid([MethodChannel? canal]) : _canalBot = canal ?? _canal;
  final MethodChannel _canalBot;

  @override
  Future<bool> encendido() async {
    try {
      return await _canalBot.invokeMethod<bool>('encendido') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> encender({required String codigo, required String datos, required String numero}) =>
      _canalBot.invokeMethod('encender', {'codigo': codigo, 'datos': datos, 'numero': numero});

  @override
  Future<void> apagar() async {
    try {
      await _canalBot.invokeMethod('apagar');
    } catch (_) {}
  }

  @override
  Future<String?> faltante() async {
    final libs = await carpetaLibrerias();
    if (libs != null && !File(p.join(libs, 'libns_node.so')).existsSync()) return 'Esta versión de la app no trae el bot. Actualizala.';
    return null;
  }

  @override
  Future<bool> sinRestriccionesDeBateria() async {
    try {
      return await _canalBot.invokeMethod<bool>('sinRestricciones') ?? false;
    } catch (_) {
      return true; // si no se puede saber, no molestar
    }
  }

  @override
  Future<void> pedirSinRestriccionesDeBateria() async {
    try {
      await _canalBot.invokeMethod('pedirSinRestricciones');
    } catch (_) {}
  }
}

class BotEnCelular {
  BotEnCelular({required this.acceso, Future<Directory> Function()? soporte, MethodChannel? canal, MotorBot? motor, Future<ByteData> Function()? zip})
      : _soporte = soporte ?? getApplicationSupportDirectory,
        _motor = motor ?? MotorBotAndroid(canal),
        _zip = zip ?? (() => rootBundle.load('assets/bot/bot.zip'));

  final AccesoBot acceso;
  final Future<Directory> Function() _soporte;
  final MotorBot _motor;
  final Future<ByteData> Function() _zip;

  Future<Directory> datos() async => Directory(p.join((await _soporte()).path, 'bot-datos'));

  /// Si la dueña lo dejó encendido (Android, o el supervisor en Windows, lo siguen manteniendo aunque la app esté cerrada).
  Future<bool> encendido() => _motor.encendido();

  /// Lo que el bot dice de sí mismo. Null si todavía no escribió nada.
  Future<EstadoBotLocal?> leerEstado() async {
    try {
      final f = File(p.join((await datos()).path, 'estado.json'));
      if (!f.existsSync()) return null;
      return EstadoBotLocal.desdeJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null; // a medio escribir: la próxima vuelta
    }
  }

  /// Las últimas líneas del registro del bot, para ver qué pasó.
  Future<List<String>> ultimasLineas([int cuantas = 60]) async {
    try {
      final f = File(p.join((await datos()).path, 'bot.log'));
      if (!f.existsSync()) return const [];
      final largo = f.lengthSync();
      final r = f.openSync();
      r.setPositionSync(max(0, largo - 16000));
      final texto = utf8.decode(r.readSync(min(largo, 16000)), allowMalformed: true);
      r.closeSync();
      final lineas = texto.split('\n').where((l) => l.trim().isNotEmpty).toList();
      return lineas.sublist(max(0, lineas.length - cuantas));
    } catch (_) {
      return const [];
    }
  }

  /// Enciende el bot para [numero] (el WhatsApp del local, `5492944…`; vacío en la compu, que vincula con el QR). Devuelve null si
  /// quedó encendido, o qué falta.
  Future<String?> encender({required String numero}) async {
    final falta = await _motor.faltante();
    if (falta != null) return falta;
    final Directory codigo;
    try {
      codigo = await preparar();
    } catch (e) {
      return 'No se pudo preparar el bot: $e';
    }
    final dirDatos = await datos();
    try {
      await asegurarCuenta(dirDatos);
    } catch (e) {
      return 'No se pudo vincular el bot a tu negocio (¿hay internet?): $e';
    }
    try {
      await _motor.encender(codigo: codigo.path, datos: dirDatos.path, numero: numero);
    } catch (e) {
      return 'No se pudo encender el bot: ${e is StateError ? e.message : e}';
    }
    // Para [ponerAlDia]: con qué número se encendió la última vez.
    try {
      File(p.join(dirDatos.path, 'numero.txt')).writeAsStringSync(numero);
    } catch (_) {}
    await _borrarVersionesViejas(codigo);
    return null;
  }

  /// Al abrir la app: si el bot está encendido, que corra el de esta versión. Después de actualizar la app, Android lo vuelve
  /// a levantar solo (`ArranqueBot`) pero con la carpeta del bot viejo, y el nuevo recién se descomprime al encender: sin esto,
  /// el bot quedaba en la versión anterior hasta que alguien tocara "Encender". Si ya está al día, Android no lo reinicia
  /// (`ServicioBot` compara la carpeta). Nunca tira.
  Future<void> ponerAlDia() async {
    try {
      if (!await encendido()) return;
      final f = File(p.join((await datos()).path, 'numero.txt'));
      // Vacío es válido: la compu vincula con el QR, sin número. Lo que no hay es el archivo (nunca se encendió desde acá).
      if (!f.existsSync()) return;
      await encender(numero: f.readAsStringSync().trim());
    } catch (_) {}
  }

  Future<void> apagar() => _motor.apagar();

  /// Borra la sesión de WhatsApp (la desvincularon, o se quiere usar otro número) y lo vuelve a encender: pide un código (o un
  /// QR) nuevo.
  Future<String?> vincularDeNuevo({required String numero}) async {
    await desvincular();
    return encender(numero: numero);
  }

  /// Lo apaga y borra la sesión de WhatsApp: queda apagado y, al encenderlo, pide vincular de nuevo. Para soltar el número sin
  /// usar otro, o cuando la sesión quedó rota (El dueño, 2026-10-21: "eliminé el dispositivo y sigue intentando reconectar").
  Future<void> desvincular() async {
    await apagar();
    final d = await datos();
    // Que Node termine de parar antes de borrarle la sesión.
    await Future<void>.delayed(_motor.esperaAlApagar);
    for (final x in [Directory(p.join(d.path, 'sesion-baileys')), File(p.join(d.path, 'estado.json'))]) {
      try {
        if (x.existsSync()) x.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Apagar y encender con el mismo número, sin tocar la vinculación: para cuando se traba reconectando.
  Future<String?> reiniciar({required String numero}) async {
    await apagar();
    await Future<void>.delayed(_motor.esperaAlApagar);
    return encender(numero: numero);
  }

  /// Si Android ya deja correr la app sin el ahorro de batería (que en muchas marcas congela las apps con la pantalla apagada).
  Future<bool> sinRestriccionesDeBateria() => _motor.sinRestriccionesDeBateria();

  Future<void> pedirSinRestriccionesDeBateria() => _motor.pedirSinRestriccionesDeBateria();

  /// Descomprime el bot en `bot/<huella>` si no está. Devuelve la carpeta.
  /// Una sola preparación a la vez (primer celular real, 2026-10-21): al abrir la app [ponerAlDia] descomprime el bot y, si en
  /// ese momento se toca "Encender" o "Vincular", una segunda llamada veía la carpeta a medias, la borraba y la primera le
  /// ponía `.listo` a lo que quedaba. El bot arrancaba sin piezas ("Cannot find package 'protobufjs'") y no se arreglaba solo.
  Future<Directory>? _preparando;

  Future<Directory> preparar() {
    final enCurso = _preparando;
    if (enCurso != null) return enCurso;
    final f = _preparar();
    _preparando = f;
    f.whenComplete(() => _preparando = null).ignore();
    return f;
  }

  /// Lo que no puede faltar: si falta, la carpeta quedó incompleta aunque diga `.listo`, y se descomprime de nuevo.
  static const _piezas = ['src/index.js', 'node_modules/@whiskeysockets/baileys/package.json', 'node_modules/protobufjs/package.json'];

  Future<Directory> _preparar() async {
    final datosZip = await _zip();
    final bytes = datosZip.buffer.asUint8List(datosZip.offsetInBytes, datosZip.lengthInBytes);
    final extras = await _motor.extras();
    // Los extras (Node de Windows, ~80 MB) entran en la huella por tamaño y fecha: leerlos enteros en cada arranque no vale la pena.
    final firmaExtras = [for (final e in extras.entries) '${e.key}:${e.value.lengthSync()}:${e.value.lastModifiedSync().millisecondsSinceEpoch}'].join('|');
    final huella = sha1.convert([...bytes, ...utf8.encode(firmaExtras)]).toString().substring(0, 12);
    final dir = Directory(p.join((await _soporte()).path, 'bot', huella));
    final listo = File(p.join(dir.path, '.listo'));
    if (listo.existsSync() && _piezas.every((x) => File(p.join(dir.path, x)).existsSync())) return dir;
    if (dir.existsSync()) dir.deleteSync(recursive: true); // quedó a medias
    dir.createSync(recursive: true);
    for (final f in ZipDecoder().decodeBytes(bytes).files) {
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
    for (final e in extras.entries) {
      e.value.copySync(p.join(dir.path, e.key));
    }
    listo.writeAsStringSync(huella);
    return dir;
  }

  Future<void> _borrarVersionesViejas(Directory enUso) async {
    try {
      for (final d in Directory(p.dirname(enUso.path)).listSync().whereType<Directory>()) {
        if (p.equals(d.path, enUso.path)) continue;
        d.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  /// `nodosur.json` del bot con un token vigente. Conserva lo que el bot anotó ahí (el cursor de pedidos, un token renovado).
  Future<void> asegurarCuenta(Directory dirDatos, {DateTime? ahora}) async {
    dirDatos.createSync(recursive: true);
    final archivo = File(p.join(dirDatos.path, 'nodosur.json'));
    Map<String, dynamic> previo = {};
    try {
      if (archivo.existsSync()) previo = Map<String, dynamic>.from(jsonDecode(archivo.readAsStringSync()) as Map);
    } catch (_) {}
    final vence = previo['expiresAt'] is num ? (previo['expiresAt'] as num).toInt() : null;
    if (previo['token'] is String && !tokenBotPorVencer(venceSegundos: vence, ahora: ahora ?? DateTime.now())) return;
    final deviceId = previo['deviceId'] is String && (previo['deviceId'] as String).startsWith('bot-') ? previo['deviceId'] as String : _idNuevo();
    final t = await acceso.tokenDelBot(deviceId);
    final cuenta = {...previo, 'sitio': t.sitio, 'token': t.token, 'email': t.email, 'deviceId': deviceId, 'expiresAt': t.expiresAt};
    previo.putIfAbsent('vinculadoEn', () => DateTime.now().toUtc().toIso8601String());
    final tmp = File('${archivo.path}.tmp')..writeAsStringSync(jsonEncode({...cuenta, 'vinculadoEn': previo['vinculadoEn']}));
    tmp.renameSync(archivo.path);
  }

  static String _idNuevo() {
    final r = Random.secure();
    return 'bot-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }
}
