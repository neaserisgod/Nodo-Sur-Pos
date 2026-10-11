// El bot adentro de Nodo Sur Servicios (`lib/servicios/bot_en_celular.dart`): descomprimir por versión y el token del bot.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/bot_en_celular.dart';
import 'package:path/path.dart' as p;

import '../helpers/sitio_bot_falso.dart';

ByteData _zipCon(Map<String, String> archivos) {
  final a = Archive();
  archivos.forEach((n, c) => a.addFile(ArchiveFile.bytes(n, utf8.encode(c))));
  final bytes = Uint8List.fromList(ZipEncoder().encode(a));
  return ByteData.sublistView(bytes);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bot_celular'));
  tearDown(() => tmp.deleteSync(recursive: true));

  BotEnCelular bot(SitioBotFalso sitio, ByteData zip) => BotEnCelular(acceso: sitio, soporte: () async => tmp, zip: () async => zip);

  test('descomprime una vez por versión; otra versión va a otra carpeta; nada se escapa de la carpeta', () async {
    final sitio = SitioBotFalso();
    final v1 = await bot(sitio, _zipCon({'src/index.js': 'uno', '../afuera.js': 'no'})).preparar();
    expect(File(p.join(v1.path, 'src/index.js')).readAsStringSync(), 'uno');
    expect(File(p.join(tmp.path, 'bot', 'afuera.js')).existsSync(), isFalse);
    expect(File(p.join(tmp.path, 'afuera.js')).existsSync(), isFalse);
    File(p.join(v1.path, 'src/index.js')).writeAsStringSync('tocado');
    expect((await bot(sitio, _zipCon({'src/index.js': 'uno', '../afuera.js': 'no'})).preparar()).path, v1.path);
    expect(File(p.join(v1.path, 'src/index.js')).readAsStringSync(), 'tocado', reason: 'ya estaba: no la vuelve a escribir');
    final v2 = await bot(sitio, _zipCon({'src/index.js': 'dos'})).preparar();
    expect(v2.path, isNot(v1.path));
  });

  test('el token del bot: se pide una vez, se conserva lo que anotó el bot y se renueva cerca de vencer', () async {
    final sitio = SitioBotFalso();
    final b = bot(sitio, _zipCon({}));
    final datos = await b.datos();
    await b.asegurarCuenta(datos);
    final f = File(p.join(datos.path, 'nodosur.json'));
    var j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(j['token'], 'token-bot-1');
    expect(j['sitio'], 'https://sitio.prueba');
    expect((j['deviceId'] as String).startsWith('bot-'), isTrue);
    final id = j['deviceId'];

    // El bot anota su cursor; la app no lo pisa ni pide otro token.
    f.writeAsStringSync(jsonEncode({...j, 'cursorPedidos': 42}));
    await b.asegurarCuenta(datos);
    expect(sitio.tokensPedidos, hasLength(1));

    // Cerca de vencer: otro token para el MISMO bot, y el cursor sigue.
    final dentroDeUnAnio = DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as int) * 1000).subtract(const Duration(days: 10));
    await b.asegurarCuenta(datos, ahora: dentroDeUnAnio);
    j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(sitio.tokensPedidos, [id, id]);
    expect(j['token'], 'token-bot-2');
    expect(j['cursorPedidos'], 42);
  });

  test('al abrir la app después de actualizarla, el bot encendido pasa a la versión nueva con el mismo número', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const canal = MethodChannel('prueba/bot-al-dia');
    final llamadas = <MethodCall>[];
    var encendido = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      llamadas.add(c);
      if (c.method == 'encendido') return encendido;
      if (c.method == 'encender') encendido = true;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));
    BotEnCelular version(String codigo) =>
        BotEnCelular(acceso: SitioBotFalso(), soporte: () async => tmp, canal: canal, zip: () async => _zipCon({'src/index.js': codigo}));

    // Apagado: no se enciende solo.
    await version('uno').ponerAlDia();
    expect(llamadas.where((c) => c.method == 'encender'), isEmpty);

    expect(await version('uno').encender(numero: '5492944123456'), isNull);
    final v1 = (llamadas.last.arguments as Map)['codigo'] as String;

    await version('dos').ponerAlDia();
    final ultima = llamadas.last.arguments as Map;
    expect(llamadas.last.method, 'encender');
    expect(ultima['codigo'], isNot(v1));
    expect(ultima['numero'], '5492944123456');
    expect(File(p.join(ultima['codigo'] as String, 'src/index.js')).readAsStringSync(), 'dos');
    expect(Directory(v1).existsSync(), isFalse, reason: 'la versión vieja se borra');
  });
}
