// El bot de WhatsApp adentro de Nodo Sur Servicios de Windows (El dueño, 2026-10-15: "el bot también en la PC",
// `docs/PLAN-ESCRITORIO-SERVICIOS.md`). Lo que en Android hace `ServicioBot.kt` lo hace acá `windows/bot/supervisor.js`, que
// corre con el Node de Windows que trae la app (`<app>\bot\node.exe`, lo baja `tool/preparar_bot_windows.ps1`):
//  * el bot es el mismo `bot.zip` del Android (JavaScript puro, con el SQLite que trae Node);
//  * Node y el supervisor se copian a la carpeta de cada versión del bot, junto al código (`BotEnCelular.preparar`): así nada
//    corre desde la carpeta de la app y el instalador la puede pisar al actualizar con el bot andando;
//  * se enciende y se apaga escribiendo `arranque.json` en la carpeta de datos: el supervisor lo mira cada 3 segundos;
//  * arranca solo al iniciar sesión en Windows por la clave Run del usuario, que llama a la app con `--bot` (la app lanza el
//    supervisor oculto y termina, `windows/runner/main.cpp`): sin ventana negra.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'bot_en_celular.dart';

/// El nombre del valor en `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (lo borra también el desinstalador).
const valorArranqueBot = 'NodoSurServiciosBot';
const _claveRun = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

class MotorBotWindows extends MotorBot {
  MotorBotWindows({required this.datos, String? carpetaInstalada, String? ejecutable, Future<ProcessResult> Function(String, List<String>)? correr, Future<void> Function(String, List<String>, String)? lanzar})
      : _ejecutable = ejecutable ?? Platform.resolvedExecutable,
        _carpetaInstalada = carpetaInstalada ?? p.join(p.dirname(ejecutable ?? Platform.resolvedExecutable), 'bot'),
        _correr = correr ?? Process.run,
        _lanzar = lanzar ?? _lanzarOculto;

  /// La carpeta de datos del bot (`bot-datos`).
  final Future<Directory> Function() datos;
  final String _ejecutable;
  final String _carpetaInstalada;
  final Future<ProcessResult> Function(String, List<String>) _correr;
  final Future<void> Function(String, List<String>, String) _lanzar;

  File get _node => File(p.join(_carpetaInstalada, 'node.exe'));
  File get _supervisor => File(p.join(_carpetaInstalada, 'supervisor.js'));

  /// El bot que trae esta instalación (el mismo del Android).
  File get zip => File(p.join(_carpetaInstalada, 'bot.zip'));

  Future<ByteData> leerZip() async => ByteData.sublistView(await zip.readAsBytes());

  @override
  Future<String?> faltante() async {
    if (!_node.existsSync() || !_supervisor.existsSync() || !zip.existsSync()) {
      return 'Esta versión de la app no trae el bot. Actualizala.';
    }
    return null;
  }

  @override
  Future<Map<String, File>> extras() async => {'node.exe': _node, 'supervisor.js': _supervisor};

  // El supervisor mira `arranque.json` cada 3 s y le da al bot hasta 10 s para cerrar.
  @override
  Duration get esperaAlApagar => const Duration(seconds: 6);

  Future<File> _arranque() async => File(p.join((await datos()).path, 'arranque.json'));

  Future<Map<String, dynamic>> _leerArranque() async {
    try {
      return Map<String, dynamic>.from(jsonDecode(await (await _arranque()).readAsString()) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _escribirArranque(Map<String, dynamic> valor) async {
    final f = await _arranque();
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp')..writeAsStringSync(jsonEncode(valor));
    tmp.renameSync(f.path);
  }

  @override
  Future<bool> encendido() async => (await _leerArranque())['encendido'] == true;

  @override
  Future<void> encender({required String codigo, required String datos, required String numero}) async {
    await _escribirArranque({'encendido': true, 'codigo': codigo, 'numero': numero});
    final node = p.join(codigo, 'node.exe');
    final supervisor = p.join(codigo, 'supervisor.js');
    // Al iniciar sesión: la app con --bot lanza esto mismo oculto (`main.cpp`). Se reescribe en cada encendido porque la
    // carpeta del bot cambia con cada versión.
    final comando = '"$_ejecutable" --bot "$node" "$supervisor" "$datos"';
    final r = await _correr('reg', ['add', _claveRun, '/v', valorArranqueBot, '/t', 'REG_SZ', '/d', comando, '/f']);
    if (r.exitCode != 0) throw StateError('Windows no dejó que arranque solo al prender la compu (${r.stderr})'.trim());
    // Ahora: si ya hay un supervisor de esta versión andando, el nuevo ve que el lugar está tomado y se va solo.
    await _lanzar(node, [supervisor, datos], codigo);
  }

  @override
  Future<void> apagar() async {
    try {
      await _escribirArranque({...await _leerArranque(), 'encendido': false});
    } catch (_) {}
    try {
      await _correr('reg', ['delete', _claveRun, '/v', valorArranqueBot, '/f']);
    } catch (_) {}
  }
}

/// Lanza Node sin consola y sin atarlo a la app: sigue andando aunque se cierre la ventana.
Future<void> _lanzarOculto(String ejecutable, List<String> argumentos, String carpeta) async {
  await Process.start(ejecutable, argumentos, workingDirectory: carpeta, mode: ProcessStartMode.detached);
}
