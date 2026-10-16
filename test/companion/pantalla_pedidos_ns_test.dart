import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_pedidos_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

/// Los pedidos de una rotisería en el celular (`REGLAS-NEGOCIO.md` §22, etapa 4): el estado de la cocina con un toque, la
/// lista por estado con el paso que sigue, y tomar un pedido del mostrador.
void main() {
  late AppDatabase db;
  late int usuario;
  late int milanesa;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    milanesa = await crearProducto(db, nombre: 'Milanesa con papas', precioCentavos: 650000, usuarioId: usuario);
  });
  tearDown(() => db.close());

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: Scaffold(body: PantallaPedidosNs(db: db, usuarioId: usuario))));
    await esperar(tester);
  }

  testWidgets('sin pedidos lo dice, y la cocina cambia con un toque', (tester) async {
    await abrir(tester);
    expect(find.text('Nada pendiente'), findsOneWidget);
    expect(find.textContaining('30 minutos'), findsOneWidget);

    await tester.tap(find.text('Pausada'));
    await esperar(tester);
    expect(await tester.runAsync(() => estadoCocinaActual(db)), EstadoCocina.pausada);
    expect(find.textContaining('no toma pedidos'), findsWidgets);
    await tester.pump(const Duration(seconds: 3)); // que se vaya el aviso de arriba
  });

  testWidgets('un pedido de WhatsApp se acepta y pasa a "por hacer", y de ahí a listo', (tester) async {
    final producto = (await tester.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(milanesa))).getSingle()))!;
    await tester.runAsync(() => crearPedido(db,
        canal: CanalPedido.whatsapp,
        nombreCliente: 'Caro',
        lineas: [LineaPedido(gid: producto.globalId!, nombre: producto.nombre, cantidad: 2, precioCentavos: 650000)],
        usuarioId: usuario));
    await abrir(tester);
    expect(find.text('1 abiertos'), findsOneWidget);
    expect(find.text('POR CONFIRMAR'), findsOneWidget);
    expect(find.text('Caro'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await esperar(tester);
    expect(find.text('POR HACER'), findsOneWidget);

    await tester.tap(find.text('Está listo'));
    await esperar(tester);
    expect(find.text('LISTO'), findsOneWidget);
    // Un retiro listo se cobra cuando lo vienen a buscar: "Cobrar" primero, "Entregado" para el que ya pagó.
    expect(find.text('Cobrar'), findsOneWidget);
    expect(find.text('Entregado'), findsOneWidget);
  });

  testWidgets('"Cobrar" manda el pedido a Cobrar', (tester) async {
    final producto = (await tester.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(milanesa))).getSingle()))!;
    final id = (await tester.runAsync(() => crearPedido(db,
        canal: CanalPedido.mostrador,
        nombreCliente: 'Juan',
        lineas: [LineaPedido(gid: producto.globalId!, nombre: producto.nombre, cantidad: 1, precioCentavos: 650000)],
        usuarioId: usuario)))!;
    final controlador = ControladorFalsoNs();
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(controlador: controlador, version: 0, child: Scaffold(body: PantallaPedidosNs(db: db, usuarioId: usuario))),
    ));
    await esperar(tester);
    await tester.tap(find.text('Cobrar'));
    await esperar(tester);
    expect(controlador.pedidosCobrados, [id]);
  });

  testWidgets('el "+" toma un pedido del mostrador con lo que elegís de la carta', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('pedidos_nuevo')));
    await esperar(tester);
    expect(find.text('Elegí qué lleva'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byKey(const Key('nuevo_pedido_nombre')), matching: find.byType(TextField)), 'Juan');
    final stepper = find.byKey(ValueKey('nuevo_pedido_plato_$milanesa'));
    await tester.tap(find.descendant(of: stepper, matching: find.byType(GestureDetector)).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Tomar pedido'), findsOneWidget);

    await tester.tap(find.textContaining('Tomar pedido'));
    await esperar(tester);
    final pedidos = (await tester.runAsync(() => pedidosAbiertos(db)))!;
    expect(pedidos.single.nombreCliente, 'Juan');
    expect(EstadoPedido.desdeClave(pedidos.single.estado), EstadoPedido.porHacer);
    expect(find.text('Juan'), findsOneWidget);
  });
}
