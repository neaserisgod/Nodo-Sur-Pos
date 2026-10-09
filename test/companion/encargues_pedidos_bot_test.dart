// Pedidos del bot de WhatsApp en Encargues (`docs/PLAN-BOT.md`): aparecen por confirmar, Aceptar los aparta, sin stock dice qué
// falta y no acepta, Rechazar no toca nada, y un pedido nuevo aparece solo cuando el sitio avisa.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_encargues_companion.dart';
import 'package:la_plazoleta/companion/pedidos_bot.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/servicios/avisos_bot.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/sitio_bot_falso.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

PedidoBot _pedido(String gid, {int id = 7, int cantidad = 2}) => PedidoBot(
  id: id,
  estado: EstadoPedidoBot.porConfirmar,
  clienteNombre: 'Sofi',
  clienteTelefono: '5492944555555',
  items: [ItemPedidoBot(gid: gid, nombre: 'Cerveza', cantidad: cantidad, precioCentavos: 150000)],
  nota: 'Paso a las 19',
  creado: DateTime(2026, 10, 9, 18, 5),
  actualizado: 1,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late PuertoLocal puerto;
  late AppDatabase db;
  late int cerveza;
  late String gid;
  late SitioBotFalso sitio;

  Future<void> preparar(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    puerto = PuertoLocal(baseLocalCompanion());
    final provs = (await t.runAsync(() => puerto.proveedores()))!;
    cerveza = (await t.runAsync(() => puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 3, proveedorId: provs[0].id, usuarioId: 1)))!;
    gid = (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(cerveza))).getSingle()))!.globalId!;
    sitio = SitioBotFalso();
  }

  Future<int> stock(WidgetTester t) async =>
      (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(cerveza))).getSingle()))!.stock;

  Future<void> abrir(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaEncarguesCompanion(servicio: puerto, usuarioId: 1, bot: sitio, registroBot: RegistroPedidosBotEnMemoria()),
    ));
    await _asentar(t);
  }

  testWidgets('el pedido aparece por confirmar con lo que pidió; Aceptar lo aparta y le avisa al sitio', (t) async {
    await preparar(t);
    sitio.pedidos.add(_pedido(gid));
    await abrir(t);
    expect(find.text('POR CONFIRMAR · WHATSAPP'), findsOneWidget);
    expect(find.text('2 × Cerveza'), findsOneWidget);
    expect(find.text('Nota: Paso a las 19'), findsOneWidget);

    await t.tap(find.byKey(const Key('pedido_bot_aceptar_7')));
    await _asentar(t);
    expect(sitio.resueltos, [(id: 7, aceptado: true)]);
    expect(await stock(t), 1);
    expect(find.byKey(const Key('pedido_bot_7')), findsNothing);
    expect(find.text('Sofi (WhatsApp)'), findsOneWidget, reason: 'queda como un encargue más');
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('sin stock no acepta, dice qué falta y deja rechazar desde ahí', (t) async {
    await preparar(t);
    sitio.pedidos.add(_pedido(gid, cantidad: 5));
    await abrir(t);
    await t.tap(find.byKey(const Key('pedido_bot_aceptar_7')));
    await _asentar(t);
    expect(find.text('No alcanza para el pedido de Sofi'), findsOneWidget);
    expect(find.text('Cerveza: piden 5, quedan 3'), findsOneWidget);
    expect(sitio.resueltos, isEmpty);
    expect(await stock(t), 3);

    await t.tap(find.text('Rechazar el pedido'));
    await _asentar(t);
    expect(sitio.resueltos, [(id: 7, aceptado: false)]);
    expect(find.byKey(const Key('pedido_bot_7')), findsNothing);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Rechazar pide confirmación y no toca el stock', (t) async {
    await preparar(t);
    sitio.pedidos.add(_pedido(gid));
    await abrir(t);
    await t.tap(find.byKey(const Key('pedido_bot_rechazar_7')));
    await _asentar(t);
    await t.tap(find.text('Rechazar').last);
    await _asentar(t);
    expect(sitio.resueltos, [(id: 7, aceptado: false)]);
    expect(await stock(t), 3);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('un pedido nuevo aparece solo cuando el sitio avisa', (t) async {
    await preparar(t);
    await abrir(t);
    expect(find.text('POR CONFIRMAR · WHATSAPP'), findsNothing);
    sitio.pedidos.add(_pedido(gid, id: 9));
    avisarPedidoBot(9);
    await _asentar(t);
    expect(find.byKey(const Key('pedido_bot_9')), findsOneWidget);
  });

  testWidgets('sin el bot (sin plan, sin cuenta o sin internet) Encargues anda igual', (t) async {
    await preparar(t);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaEncarguesCompanion(servicio: puerto, usuarioId: 1, bot: _SitioQueFalla()),
    ));
    await _asentar(t);
    expect(find.text('No hay encargues pendientes.'), findsOneWidget);
    expect(find.byKey(const Key('encargues_error')), findsNothing);
  });
}

class _SitioQueFalla extends SitioBotFalso {
  @override
  Future<List<PedidoBot>> porConfirmar() async => throw Exception('sin_plan_bot');
}
