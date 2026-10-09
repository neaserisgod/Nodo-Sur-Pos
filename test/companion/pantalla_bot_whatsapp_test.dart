// Pantalla "Bot de WhatsApp" del celular (`docs/PLAN-BOT.md`): el estado para todos, la configuración y la instalación solo
// para quien puede configurar, el nombre y el rubro de Configuración, y lo que el bot rechazaría no se guarda.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_bot_whatsapp.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/sitio_bot_falso.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

final _ahora = DateTime(2026, 10, 9, 12);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late PuertoLocal puerto;
  late SitioBotFalso sitio;
  var rubroPedido = 0;

  Future<void> preparar(WidgetTester t, {bool conRubro = true, String nombre = 'Almacén Don Pepe'}) async {
    t.view.physicalSize = const Size(420, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    puerto = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() async {
      await configurarNombreComercio(db, nombre);
      if (conRubro) await configurarRubro(db, PlantillaRubro.desdeClave('almacen')!);
    });
    sitio = SitioBotFalso();
    rubroPedido = 0;
  }

  Future<void> abrir(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaBotWhatsApp(acceso: sitio, servicio: puerto, ahora: () => _ahora, alIrATuNegocio: () => rubroPedido++),
    ));
    await _asentar(t);
  }

  testWidgets('quien no configura ve si anda, y nada de configuración ni instalación', (t) async {
    await preparar(t);
    sitio.estadoBot = EstadoBot(tieneBot: true, bots: [BotVinculado(nombre: 'Bot', ultimaSenal: _ahora.subtract(const Duration(minutes: 20)))]);
    await abrir(t);
    expect(find.textContaining('Andando'), findsOneWidget);
    expect(find.byKey(const Key('bot_guardar')), findsNothing);
    expect(find.byKey(const Key('bot_copiar')), findsNothing);
    expect(find.textContaining('dueño o un encargado'), findsOneWidget);
  });

  testWidgets('sin señal hace más de dos horas lo dice con qué revisar', (t) async {
    await preparar(t);
    sitio.estadoBot = EstadoBot(tieneBot: true, bots: [BotVinculado(nombre: 'Bot', ultimaSenal: _ahora.subtract(const Duration(hours: 5)))]);
    await abrir(t);
    expect(find.textContaining('Sin señal desde 9/10 07:00'), findsOneWidget);
  });

  testWidgets('el dueño carga números y horarios; se guarda con el nombre y el rubro de Configuración', (t) async {
    await preparar(t);
    await abrir(t);
    expect(find.textContaining('Todavía no hay un bot instalado'), findsOneWidget);
    expect(find.text('Almacén Don Pepe · Almacén'), findsOneWidget);

    await t.enterText(find.descendant(of: find.byKey(const Key('bot_numero')), matching: find.byType(TextField)), '2944 111111');
    await t.enterText(find.descendant(of: find.byKey(const Key('bot_avisos')), matching: find.byType(TextField)), '02944-222222');
    await t.enterText(find.descendant(of: find.byKey(const Key('bot_direccion')), matching: find.byType(TextField)), 'Mitre 123');
    await t.tap(find.byKey(const Key('bot_pausa_30')));
    await t.pump();
    await t.tap(find.byKey(const Key('bot_guardar')));
    await _asentar(t);

    final c = sitio.configGuardada!;
    expect(c['numero_actual'], '5492944111111');
    expect(c['numero_duena'], '5492944222222');
    expect(c['negocio'], {'nombre': 'Almacén Don Pepe', 'rubro': 'almacen', 'direccion': 'Mitre 123'});
    expect(c['pausa_minutos'], 30);
    expect((c['horarios'] as Map)['domingo'], isNull);
    expect((c['horarios'] as Map)['sabado'], {'desde': '09:00', 'hasta': '13:00'});
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('lo que el bot rechazaría no se guarda y dice por qué', (t) async {
    await preparar(t);
    await abrir(t);
    await t.enterText(find.descendant(of: find.byKey(const Key('bot_numero')), matching: find.byType(TextField)), '2944 111111');
    await t.enterText(find.descendant(of: find.byKey(const Key('bot_avisos')), matching: find.byType(TextField)), '2944 111111');
    await t.tap(find.byKey(const Key('bot_guardar')));
    await _asentar(t);
    expect(sitio.configGuardada, isNull);
    expect(find.textContaining('tiene que ser otro que el del bot'), findsOneWidget);
  });

  testWidgets('sin rubro manda a elegirlo y no deja guardar', (t) async {
    await preparar(t, conRubro: false);
    await abrir(t);
    expect(find.text('Almacén Don Pepe · Rubro sin elegir'), findsOneWidget);
    await t.tap(find.byKey(const Key('bot_elegir_rubro')));
    expect(rubroPedido, 1);
    await t.tap(find.byKey(const Key('bot_guardar')));
    await _asentar(t);
    expect(sitio.configGuardada, isNull);
    expect(find.textContaining('Elegí el rubro'), findsOneWidget);
  });

  testWidgets('lo guardado vuelve a aparecer al abrir, y lo que la app no edita se conserva', (t) async {
    await preparar(t);
    sitio.configGuardada = {
      'numero_actual': '5492944111111',
      'numero_duena': '5492944222222',
      'negocio': {'nombre': 'Viejo', 'rubro': 'almacen', 'direccion': 'Mitre 123'},
      'horarios': {for (final d in diasBot) d: d == 'domingo' ? null : {'desde': '08:00', 'hasta': '21:00'}},
      'pausa_minutos': 90,
      'textos': {'quien_atiende': 'Pepe'},
    };
    await abrir(t);
    expect(find.text('2944 111111'), findsOneWidget);
    expect(find.text('Mitre 123'), findsOneWidget);
    expect(find.byKey(const Key('bot_pausa_90')), findsOneWidget, reason: 'una pausa que no está entre las de siempre igual se muestra');
    await t.tap(find.byKey(const Key('bot_guardar')));
    await _asentar(t);
    expect(sitio.configGuardada!['textos'], {'quien_atiende': 'Pepe'});
    expect((sitio.configGuardada!['negocio'] as Map)['nombre'], 'Almacén Don Pepe');
    expect((sitio.configGuardada!['horarios'] as Map)['lunes'], {'desde': '08:00', 'hasta': '21:00'});
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('instalar: los pasos y el comando para copiar', (t) async {
    await preparar(t);
    String? copiado;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await abrir(t);
    expect(find.text(comandoInstalarBot), findsOneWidget);
    await t.tap(find.byKey(const Key('bot_copiar')));
    await _asentar(t);
    expect(copiado, comandoInstalarBot);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('sin plan o sin cuenta vinculada lo dice en vez de romper', (t) async {
    await preparar(t);
    sitio.estadoBot = null;
    await abrir(t);
    expect(find.textContaining('vinculá este celular'), findsOneWidget);
  });
}
