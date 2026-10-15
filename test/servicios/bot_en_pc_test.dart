// El bot adentro de Nodo Sur Servicios de Windows (`lib/servicios/bot_en_pc.dart`): Node y el supervisor viajan con cada versión
// del bot, se enciende y apaga por `arranque.json` y arranca solo con Windows por la clave Run.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/bot_en_celular.dart';
import 'package:la_plazoleta/servicios/bot_en_pc.dart';
import 'package:path/path.dart' as p;

import '../helpers/sitio_bot_falso.dart';

void main() {
  late Directory tmp;
  late Directory instalada;
  late List<List<String>> comandos;
  late List<(String, List<String>, String)> lanzados;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bot_pc');
    instalada = Directory(p.join(tmp.path, 'app', 'bot'))..createSync(recursive: true);
    comandos = [];
    lanzados = [];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void instalarBot({String codigo = 'uno'}) {
    final a = Archive()..addFile(ArchiveFile.bytes('src/index.js', utf8.encode(codigo)));
    File(p.join(instalada.path, 'bot.zip')).writeAsBytesSync(ZipEncoder().encode(a));
    File(p.join(instalada.path, 'node.exe')).writeAsStringSync('node');
    File(p.join(instalada.path, 'supervisor.js')).writeAsStringSync('supervisor');
  }

  BotEnCelular armar() {
    late final BotEnCelular bot;
    final motor = MotorBotWindows(
      datos: () => bot.datos(),
      ejecutable: p.join(tmp.path, 'app', 'nodo_sur_servicios.exe'),
      correr: (programa, args) async {
        comandos.add([programa, ...args]);
        return ProcessResult(0, 0, '', '');
      },
      lanzar: (programa, args, carpeta) async => lanzados.add((programa, args, carpeta)),
    );
    bot = BotEnCelular(acceso: SitioBotFalso(), soporte: () async => Directory(p.join(tmp.path, 'datos')), motor: motor, zip: motor.leerZip);
    return bot;
  }

  Map<String, dynamic> arranque() =>
      jsonDecode(File(p.join(tmp.path, 'datos', 'bot-datos', 'arranque.json')).readAsStringSync()) as Map<String, dynamic>;

  test('sin Node o sin el bot en la instalación: dice que hay que actualizar y no toca nada', () async {
    final bot = armar();
    expect(await bot.encender(numero: '5492944123456'), contains('no trae el bot'));
    expect(comandos, isEmpty);
    expect(lanzados, isEmpty);
  });

  test('encender: copia Node y el supervisor con el bot, deja arranque.json, la clave Run y lanza el supervisor oculto', () async {
    instalarBot();
    final bot = armar();
    expect(await bot.encender(numero: '5492944123456'), isNull);

    final a = arranque();
    expect(a['encendido'], isTrue);
    expect(a['numero'], '5492944123456');
    final codigo = a['codigo'] as String;
    for (final f in ['node.exe', 'supervisor.js', 'src/index.js']) {
      expect(File(p.join(codigo, f)).existsSync(), isTrue, reason: f);
    }
    expect(await bot.encendido(), isTrue);

    final reg = comandos.single;
    expect(reg.take(2), ['reg', 'add']);
    expect(reg, contains(valorArranqueBot));
    final valor = reg[reg.indexOf('/d') + 1];
    // Arranca con la app (que lo lanza oculto), nunca con node.exe directo: abriría una ventana de consola.
    expect(valor, startsWith('"${p.join(tmp.path, 'app', 'nodo_sur_servicios.exe')}" --bot "${p.join(codigo, 'node.exe')}"'));

    final (programa, args, carpeta) = lanzados.single;
    expect(programa, p.join(codigo, 'node.exe'), reason: 'Node corre desde la carpeta del bot, no desde la de la app');
    expect(args, [p.join(codigo, 'supervisor.js'), p.join(tmp.path, 'datos', 'bot-datos')]);
    expect(carpeta, codigo);
  });

  test('apagar: arranque.json queda apagado (con lo demás) y se borra la clave Run', () async {
    instalarBot();
    final bot = armar();
    await bot.encender(numero: '5492944123456');
    comandos.clear();
    await bot.apagar();
    expect(arranque()['encendido'], isFalse);
    expect(arranque()['numero'], '5492944123456');
    expect(await bot.encendido(), isFalse);
    expect(comandos.single.take(2), ['reg', 'delete']);
  });

  test('una versión nueva de la app (otro Node o otro bot) va a otra carpeta y la clave Run apunta a la nueva', () async {
    instalarBot();
    final bot = armar();
    await bot.encender(numero: '5492944123456');
    final v1 = arranque()['codigo'] as String;

    instalarBot(codigo: 'dos');
    await bot.ponerAlDia();
    final v2 = arranque()['codigo'] as String;
    expect(v2, isNot(v1));
    expect(comandos.last[comandos.last.indexOf('/d') + 1], contains(p.join(v2, 'supervisor.js')));
    expect(File(p.join(v2, 'src', 'index.js')).readAsStringSync(), 'dos');
  });

  test('Windows no deja escribir la clave Run: se dice, sin lanzar nada', () async {
    instalarBot();
    late final BotEnCelular bot;
    final motor = MotorBotWindows(
      datos: () => bot.datos(),
      ejecutable: p.join(tmp.path, 'app', 'nodo_sur_servicios.exe'),
      correr: (_, _) async => ProcessResult(0, 1, '', 'Acceso denegado'),
      lanzar: (programa, args, carpeta) async => lanzados.add((programa, args, carpeta)),
    );
    bot = BotEnCelular(acceso: SitioBotFalso(), soporte: () async => Directory(p.join(tmp.path, 'datos')), motor: motor, zip: motor.leerZip);
    expect(await bot.encender(numero: '5492944123456'), contains('Acceso denegado'));
    expect(lanzados, isEmpty);
  });

  test('el zip del bot se lee de la carpeta de la app', () async {
    instalarBot();
    final motor = MotorBotWindows(datos: () async => tmp, ejecutable: p.join(tmp.path, 'app', 'nodo_sur_servicios.exe'));
    final bytes = await motor.leerZip();
    expect(bytes, isA<ByteData>());
    expect(bytes.lengthInBytes, File(p.join(instalada.path, 'bot.zip')).lengthSync());
  });
}
