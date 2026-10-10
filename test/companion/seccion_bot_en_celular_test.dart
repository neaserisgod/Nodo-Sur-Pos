// "En este celular" en Bot de WhatsApp (Nodo Sur Servicios): estado, código para vincular y encender.
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

  Future<void> abrir(WidgetTester t, {String? numero = '5492944123456'}) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(builder: (c) => Scaffold(backgroundColor: c.ns.paper, body: ListView(children: [SeccionBotEnCelularNs(bot: bot(), numeroBot: numero)]))),
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
}
