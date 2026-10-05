// Encargues del celular (2026-10-02): apartar saca el stock, cancelar lo devuelve, y "Entregar" le pasa el encargue al
// menú. Se prueba contra una base real (el mismo camino que sin PC), no contra un doble.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_encargues_companion.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart' show ApartadoCompanion;
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';

import '../helpers/base_para_tests.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late PuertoLocal puerto;
  late AppDatabase db;
  late int cerveza;

  Future<void> preparar(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    puerto = PuertoLocal(baseLocalCompanion());
    final provs = (await t.runAsync(() => puerto.proveedores()))!;
    cerveza = (await t.runAsync(() => puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: provs[0].id, usuarioId: 1)))!;
  }

  Future<int> stock(WidgetTester t) async =>
      (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(cerveza))).getSingle()))!.stock;

  Future<void> abrir(WidgetTester t, {bool ventaArmada = false, int? sesionCajaId, void Function(EntregaEncargue?)? alVolver}) async {
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                // Ojo: `alVolver?.call(await ...)` no evaluaría el push si alVolver es null.
                final entrega = await Navigator.of(context).push<EntregaEncargue>(MaterialPageRoute(
                  builder: (_) => PantallaEncarguesCompanion(servicio: puerto, usuarioId: 1, hayVentaArmada: ventaArmada, sesionCajaId: sesionCajaId),
                ));
                alVolver?.call(entrega);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await _asentar(t);
  }

  testWidgets('sin encargues lo dice; "Nuevo encargue" aparta, baja el stock y aparece en la lista', (t) async {
    await preparar(t);
    await abrir(t);
    expect(find.text('No hay encargues pendientes.'), findsOneWidget);

    await t.tap(find.byKey(const Key('encargue_nuevo')));
    await _asentar(t);
    await t.enterText(find.byKey(const Key('encargue_nombre')), 'María');
    await t.enterText(find.byKey(const Key('encargue_buscador')), 'cerv');
    await _asentar(t);
    await t.tap(find.byKey(Key('encargue_opcion_$cerveza')));
    await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.tap(find.bySemanticsLabel('Más'));
      await t.pump();
    }
    expect(find.text('3'), findsOneWidget);
    await t.tap(find.byKey(const Key('encargue_apartar')));
    await _asentar(t);
    await t.pumpAndSettle(); // termina de salir la pantalla de alta

    expect(await stock(t), 9);
    expect(find.text('María'), findsOneWidget);
    expect(find.text('3 × Cerveza'), findsOneWidget);
  });

  testWidgets('cancelar pide confirmación y devuelve lo apartado', (t) async {
    await preparar(t);
    await t.runAsync(() => puerto.crearEncargue(nombreCliente: 'María', lineas: [ApartadoCompanion(productoId: cerveza, cantidad: 3)], usuarioId: 1));
    await abrir(t);
    expect(await stock(t), 9);

    await t.tap(find.text('Cancelar encargue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar encargue').last);
    await _asentar(t);

    expect(await stock(t), 12);
    expect(find.text('No hay encargues pendientes.'), findsOneWidget);
  });

  testWidgets('"Entregar" devuelve el encargue al menú, que arma el carrito', (t) async {
    await preparar(t);
    final id = (await t.runAsync(() => puerto.crearEncargue(nombreCliente: 'María', lineas: [ApartadoCompanion(productoId: cerveza, cantidad: 3)], usuarioId: 1)))!;
    EntregaEncargue? entrega;
    await abrir(t, alVolver: (e) => entrega = e);

    await t.tap(find.text('Entregar'));
    await t.pumpAndSettle();
    expect(entrega?.id, id);
  });

  testWidgets('con una venta armada no se puede entregar: lo avisa y el encargue sigue pendiente', (t) async {
    await preparar(t);
    await t.runAsync(() => puerto.crearEncargue(nombreCliente: 'María', lineas: [ApartadoCompanion(productoId: cerveza, cantidad: 3)], usuarioId: 1));
    await abrir(t, ventaArmada: true);

    await t.tap(find.text('Entregar'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('encargues_error')), findsOneWidget);
    expect(find.text('María'), findsOneWidget);
  });

  testWidgets('sin stock suficiente no aparta y muestra el motivo', (t) async {
    await preparar(t);
    await abrir(t);
    await t.tap(find.byKey(const Key('encargue_nuevo')));
    await _asentar(t);
    await t.enterText(find.byKey(const Key('encargue_nombre')), 'María');
    await t.enterText(find.byKey(const Key('encargue_buscador')), 'cerv');
    await _asentar(t);
    await t.tap(find.byKey(Key('encargue_opcion_$cerveza')));
    await t.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await t.tap(find.bySemanticsLabel('Más'));
      await t.pump();
    }
    await t.tap(find.byKey(const Key('encargue_apartar')));
    await _asentar(t);

    expect(find.byKey(const Key('encargue_error')), findsOneWidget);
    expect(await stock(t), 12);
  });

  testWidgets('"Entregar y anotar deuda" pasa a Deudas y se cobra en efectivo como una venta del día', (t) async {
    await preparar(t);
    await t.runAsync(() => puerto.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0));
    // La deuda es a precio de hoy: el producto del test se creó sin precio.
    await t.runAsync(() => (db.update(db.productos)..where((p) => p.id.equals(cerveza))).write(const ProductosCompanion(precioCentavos: Value(150000))));
    final sesionId = (await t.runAsync(() => db.select(db.sesionesDeCaja).getSingle()))!.id;
    final id = (await t.runAsync(() => puerto.crearEncargue(nombreCliente: 'María', lineas: [ApartadoCompanion(productoId: cerveza, cantidad: 3)], usuarioId: 1)))!;
    await abrir(t, sesionCajaId: sesionId);

    await t.tap(find.byKey(Key('encargue_deuda_$id')));
    await t.pumpAndSettle();
    await t.tap(find.text('Entregar y anotar'));
    await _asentar(t);
    await t.pumpAndSettle();

    expect(find.byKey(Key('encargue_$id')), findsNothing);
    expect(find.text('DEUDAS'), findsOneWidget);
    expect(await stock(t), 9); // el stock ya estaba descontado al apartar

    await t.tap(find.textContaining('Cobrar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Efectivo'));
    await _asentar(t);
    await t.pumpAndSettle();

    expect(find.text('DEUDAS'), findsNothing);
    expect((await t.runAsync(() => db.select(db.ventas).get()))!, hasLength(1));
  });
}
