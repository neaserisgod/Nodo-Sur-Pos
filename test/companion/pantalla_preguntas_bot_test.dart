// Preguntas del bot (El dueño, 2026-10-21): pegar un bloque copiado, editar una pregunta y guardar encima de la configuración
// que tiene el sitio en ese momento, sin pisar lo que la app le mandó al bot mientras tanto.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_preguntas_bot_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/sitio_bot_falso.dart';

const _bloque = '''
emoji: 🍔
pagos: Efectivo al recibir o transferencia.
---
pregunta: ¿De qué es la carne?
claves: que carne, de que es la carne
respuesta: Aguja picada, 100 g cada medallón.
---
pregunta: Cerveza
claves: cerveza
respuesta: Tenemos artesanal.
''';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  }
  await t.pump();
}

void main() {
  late SitioBotFalso sitio;
  String? portapapeles;

  setUp(() {
    sitio = SitioBotFalso()..configGuardada = {'numero_actual': '5492944111111', 'textos': {'quien_atiende': 'el local'}};
    portapapeles = _bloque;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return portapapeles == null ? null : {'text': portapapeles};
      return null;
    });
  });

  Future<void> abrir(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaPreguntasBotNs(acceso: sitio, nombresCarta: const ['Cambio a cerveza artesanal']),
    ));
    await _asentar(t);
  }

  testWidgets('pegar un bloque y guardar: va encima de lo que tiene el sitio en ese momento', (t) async {
    await abrir(t);
    expect(find.text('Todavía no cargaste preguntas.'), findsOneWidget);

    await t.tap(find.byKey(const Key('pregunta_pegar')));
    await _asentar(t);
    expect(find.text('Pegar 2 preguntas'), findsOneWidget);
    await t.tap(find.text('Pegar'));
    await _asentar(t);
    expect(find.text('¿De qué es la carne?'), findsOneWidget);
    expect(find.text('Cerveza'), findsOneWidget);

    // Mientras tanto la app le mandó al bot la carta y la cocina: no se pierde.
    sitio.configGuardada = {...sitio.configGuardada!, 'pedidos': {'cocina': 'normal'}};
    await t.tap(find.byKey(const Key('pregunta_guardar')));
    await _asentar(t);

    final c = sitio.configGuardada!;
    expect(c['numero_actual'], '5492944111111');
    expect(c['pedidos'], {'cocina': 'normal'});
    expect((c['preguntas'] as List), hasLength(2));
    expect(c['respuestas'], {'pagos': 'Efectivo al recibir o transferencia.', 'envios': null});
    expect(c['textos'], {'quien_atiende': 'el local', 'emoji': '🍔'});
    await t.pump(const Duration(seconds: 5)); // que se vaya el aviso de "Guardado"
  });

  testWidgets('editar avisa una clave que es palabra de la carta, y borrar la saca', (t) async {
    sitio.configGuardada = {
      ...sitio.configGuardada!,
      'preguntas': [
        {'titulo': 'Cerveza', 'claves': ['cerveza'], 'respuesta': 'Tenemos artesanal.'}
      ],
    };
    await abrir(t);
    await t.tap(find.byKey(const Key('pregunta_0')));
    await _asentar(t);
    expect(find.textContaining('está en la carta'), findsOneWidget);

    await t.enterText(find.descendant(of: find.byKey(const Key('hoja_pregunta_claves')), matching: find.byType(TextField)), 'tienen cerveza, hay cerveza');
    await t.pump();
    expect(find.textContaining('está en la carta'), findsNothing);
    await t.tap(find.text('Listo'));
    await _asentar(t);

    await t.tap(find.byKey(const Key('pregunta_0')));
    await _asentar(t);
    await t.tap(find.text('Borrar'));
    await _asentar(t);
    expect(find.text('Todavía no cargaste preguntas.'), findsOneWidget);
  });

  testWidgets('sin configuración del bot pide cargar los números primero', (t) async {
    sitio.configGuardada = null;
    await abrir(t);
    expect(find.textContaining('Primero guardá la configuración del bot'), findsOneWidget);
  });
}
