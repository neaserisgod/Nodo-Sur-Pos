// "En este celular" en Bot de WhatsApp (Nodo Sur Servicios): estado, código (o QR en la compu) para vincular y encender.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/seccion_bot_en_celular_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/servicios/bot_en_celular.dart';
import 'package:path/path.dart' as p;

import '../helpers/sitio_bot_falso.dart';

void main() {
  late Directory tmp;
  late List<MethodCall> llamadas;
  late bool encendido;
  const canal = MethodChannel('prueba/bot');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('seccion_bot');
    llamadas = [];
    encendido = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      llamadas.add(c);
      return switch (c.method) {
        'encendido' => encendido,
        'sinRestricciones' => true,
        'encender' => (() => encendido = true)(),
        _ => null,
      };
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null);
    tmp.deleteSync(recursive: true);
  });

  // La pantalla lee archivos de verdad: dejar correr el reloj real y el de la prueba unas vueltas.
  Future<void> asentar(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
  }

  BotEnCelular bot() => BotEnCelular(acceso: SitioBotFalso(), soporte: () async => tmp, canal: canal, zip: () async => ByteData(0));

  Future<void> abrir(WidgetTester t, {String? numero = '5492944123456', bool enLaCompu = false, Future<bool> Function(String)? cambiarNumero}) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(builder: (c) => Scaffold(backgroundColor: c.ns.paper, body: ListView(children: [SeccionBotEnCelularNs(bot: bot(), numeroBot: numero, enLaCompu: enLaCompu, cambiarNumero: cambiarNumero)]))),
    ));
    await asentar(t);
  }

  testWidgets('apagado: se ofrece encenderlo; sin el número del local, avisa en vez de encender', (t) async {
    await abrir(t, numero: null);
    expect(find.text('Apagado'), findsOneWidget);
    await t.tap(find.byKey(const Key('bot_celular_encender')));
    await t.pump();
    expect(find.byKey(const Key('bot_celular_error')), findsOneWidget);
    expect(llamadas.where((c) => c.method == 'encender'), isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('encendido y sin vincular: muestra el código como lo pide WhatsApp', (t) async {
    encendido = true;
    final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync();
    File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode({'conectado': false, 'codigo': 'ABCD1234'}));
    await abrir(t);
    expect(find.text('Falta vincularlo con WhatsApp'), findsOneWidget);
    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.byKey(const Key('bot_celular_apagar')), findsOneWidget);

    File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode({'conectado': true}));
    await t.pump(const Duration(seconds: 2));
    await asentar(t);
    expect(find.text('Conectado y atendiendo'), findsOneWidget);
    expect(find.text('ABCD-1234'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('en la compu: dibuja el QR para escanear con el celular, sin código', (t) async {
    encendido = true;
    final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync();
    File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode({'conectado': false, 'qr': '2@abc,def,ghi', 'codigo': 'ABCD1234'}));
    await abrir(t, enLaCompu: true);
    expect(find.text('Falta vincularlo con WhatsApp'), findsOneWidget);
    expect(find.byKey(const Key('bot_celular_qr')), findsOneWidget);
    expect(find.text('ABCD-1234'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('en el celular: el QR no se muestra (no se escanea la propia pantalla)', (t) async {
    encendido = true;
    final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync();
    File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode({'conectado': false, 'qr': '2@abc,def,ghi', 'codigo': 'ABCD1234'}));
    await abrir(t);
    expect(find.byKey(const Key('bot_celular_qr')), findsNothing);
    expect(find.text('ABCD-1234'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('en la compu se enciende sin el número del local: vincula con el QR', (t) async {
    await abrir(t, numero: null, enLaCompu: true);
    await t.tap(find.byKey(const Key('bot_celular_encender')));
    // Encender descomprime el bot y vincula la cuenta (archivos de verdad): en una máquina lenta tarda más que [asentar].
    for (var i = 0; i < 100 && !llamadas.any((c) => c.method == 'encender'); i++) {
      await asentar(t);
    }
    expect(find.byKey(const Key('bot_celular_error')), findsNothing);
    final encender = llamadas.where((c) => c.method == 'encender').toList();
    expect(encender, hasLength(1));
    expect((encender.single.arguments as Map)['numero'], '');
    await t.pumpWidget(const SizedBox());
  });

  // Control del bot (El dueño, 2026-10-21): desvincular y vincular otro número desde la app. Apagar espera a que Node pare: el
  // reloj de la prueba se adelanta.
  Future<void> esperarApagado(WidgetTester t, bool Function() listo) async {
    for (var i = 0; i < 100 && !listo(); i++) {
      await t.pump(const Duration(milliseconds: 500));
      await asentar(t);
    }
  }

  Directory sesionDePrueba() {
    final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync();
    File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode({'conectado': true}));
    return Directory(p.join(datos.path, 'sesion-baileys'))..createSync();
  }

  testWidgets('encendido: muestra el número y el control; desvincular pide confirmar, apaga y borra la sesión', (t) async {
    encendido = true;
    final sesion = sesionDePrueba();
    await abrir(t);
    expect(find.text('WhatsApp del bot: 2944 12-3456'), findsOneWidget);
    expect(find.byKey(const Key('bot_celular_reiniciar')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('bot_celular_desvincular')));
    await t.tap(find.byKey(const Key('bot_celular_desvincular')));
    await t.pumpAndSettle();
    await t.tap(find.text('Desvincular'));
    await esperarApagado(t, () => !sesion.existsSync());
    expect(llamadas.where((c) => c.method == 'apagar'), isNotEmpty);
    expect(sesion.existsSync(), isFalse);
    expect(llamadas.where((c) => c.method == 'encender'), isEmpty, reason: 'queda apagado hasta que se vincule de nuevo');
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('vincular otro número: lo guarda en la configuración y pide el código para ese número', (t) async {
    encendido = true;
    final sesion = sesionDePrueba();
    final guardados = <String>[];
    await abrir(t, cambiarNumero: (n) async {
      guardados.add(n);
      return true;
    });
    await t.ensureVisible(find.byKey(const Key('bot_celular_otro_numero')));
    await t.tap(find.byKey(const Key('bot_celular_otro_numero')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '12');
    await t.tap(find.text('Vincular este número'));
    await t.pump();
    expect(find.textContaining('no parece de WhatsApp'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '2944 999888');
    await t.tap(find.text('Vincular este número'));
    await esperarApagado(t, () => llamadas.any((c) => c.method == 'encender'));
    expect(guardados, ['5492944999888']);
    expect(sesion.existsSync(), isFalse);
    expect((llamadas.lastWhere((c) => c.method == 'encender').arguments as Map)['numero'], '5492944999888');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('el registro se puede copiar entero', (t) async {
    final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync();
    File(p.join(datos.path, 'bot.log')).writeAsStringSync('WhatsApp conectado.\nNodo Sur (ping): fetch failed\n');
    String? copiado;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copiado = (c.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await abrir(t);
    await t.ensureVisible(find.text('Ver el registro del bot'));
    await t.tap(find.text('Ver el registro del bot'));
    await asentar(t);
    await t.ensureVisible(find.byKey(const Key('bot_celular_copiar_registro')));
    await t.tap(find.byKey(const Key('bot_celular_copiar_registro')));
    await asentar(t);
    expect(copiado, contains('fetch failed'));
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
  });
}
