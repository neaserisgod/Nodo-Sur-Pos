import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_encargues.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import 'package:la_plazoleta/ui/encargues/pantalla_encargues.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int galletitas;

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaEncargues(db: db, usuarioId: usuarioId)));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    galletitas = await crearProducto(db, nombre: 'Galletitas', precioCentavos: 150000, stock: 10, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  testWidgets('sin encargues lo dice y ofrece cargar uno', (tester) async {
    await abrir(tester);
    expect(find.byKey(const Key('encargues_vacio')), findsOneWidget);
    expect(find.text('Nuevo encargue'), findsOneWidget);
  });

  testWidgets('muestra cada encargue con lo apartado y sus dos acciones', (tester) async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );
    await abrir(tester);
    final tarjeta = find.byKey(Key('encargue_$id'));
    expect(tarjeta, findsOneWidget);
    expect(find.descendant(of: tarjeta, matching: find.text('Encargue de María')), findsOneWidget);
    expect(find.descendant(of: tarjeta, matching: find.text('3 × Galletitas')), findsOneWidget);
    expect(find.descendant(of: tarjeta, matching: find.text('Entregar')), findsOneWidget);
    expect(find.descendant(of: tarjeta, matching: find.text('Cancelar')), findsOneWidget);
  });

  testWidgets('"Nuevo encargue": se busca el producto, se elige la cantidad y al apartar baja el stock', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('Nuevo encargue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('encargue_nombre')), 'María');
    await tester.enterText(find.byKey(const Key('encargue_buscador')), 'galle');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('encargue_opcion_$galletitas')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apartar'));
    await tester.pumpAndSettle();

    expect((await (db.select(db.productos)..where((p) => p.id.equals(galletitas))).getSingle()).stock, 7);
    expect(find.text('3 × Galletitas'), findsOneWidget);
  });

  testWidgets('cancelar pide confirmación y devuelve lo apartado al stock', (tester) async {
    await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );
    await abrir(tester);
    await tester.tap(find.text('Cancelar').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('vuelve al stock'), findsOneWidget);
    await tester.tap(find.text('Cancelar encargue'));
    await tester.pumpAndSettle();

    expect((await (db.select(db.productos)..where((p) => p.id.equals(galletitas))).getSingle()).stock, 10);
    expect(find.byKey(const Key('encargues_vacio')), findsOneWidget);
  });

  testWidgets('entregar y anotar deuda: pasa a Deudas y se cobra en efectivo como una venta del día', (tester) async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: PantallaEncargues(db: db, usuarioId: usuarioId, sesionCajaId: sesionId),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byKey(Key('encargue_$id')), matching: find.text('Entregar y anotar deuda')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar y anotar'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('encargue_$id')), findsNothing);
    expect(find.text('Deudas'), findsOneWidget);
    expect(find.text('3 × Galletitas'), findsOneWidget);

    await tester.tap(find.textContaining('Cobrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Efectivo'));
    await tester.pumpAndSettle();

    expect(await listarDeudas(db), isEmpty);
    expect(await db.select(db.ventas).get(), hasLength(1));
    expect(find.text('Deudas'), findsNothing);
  });

  group('seña', () {
    Future<void> abrirConCaja(WidgetTester tester, int sesionId) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: TemaPlazoleta.oscuro,
        home: PantallaEncargues(db: db, usuarioId: usuarioId, sesionCajaId: sesionId),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sin caja abierta el alta no ofrece seña y lo explica', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('Nuevo encargue'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('encargue_sena_sin_caja')), findsOneWidget);
      expect(find.byKey(const Key('encargue_sena')), findsNothing);
    });

    testWidgets('con caja: se carga la seña, entra a la caja y la tarjeta la muestra', (tester) async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await abrirConCaja(tester, sesionId);
      await tester.tap(find.text('Nuevo encargue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('encargue_nombre')), 'María');
      await tester.enterText(find.byKey(const Key('encargue_buscador')), 'galle');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('encargue_opcion_$galletitas')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '3');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const Key('encargue_sena')), matching: find.byType(TextField)), '2000');
      await tester.tap(find.text('Apartar'));
      await tester.pumpAndSettle();

      final pendiente = await db.select(db.pendientes).getSingle();
      expect(pendiente.senaCentavos, 200000);
      expect(pendiente.senaEsEfectivo, isTrue);
      expect(find.byKey(Key('encargue_sena_${pendiente.id}')), findsOneWidget);
      expect(await db.select(db.ventas).get(), isEmpty, reason: 'la seña no es una venta');
    });

    testWidgets('una seña mayor a lo que vale se rechaza con un mensaje y no aparta nada', (tester) async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await abrirConCaja(tester, sesionId);
      await tester.tap(find.text('Nuevo encargue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('encargue_nombre')), 'María');
      await tester.enterText(find.byKey(const Key('encargue_buscador')), 'galle');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('encargue_opcion_$galletitas')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byKey(const Key('encargue_sena')), matching: find.byType(TextField)), '99999');
      await tester.tap(find.text('Apartar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('encargue_error')), findsOneWidget);
      expect(await db.select(db.pendientes).get(), isEmpty);
    });

    testWidgets('cancelar un encargue con seña avisa que se devuelve y la devuelve', (tester) async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearEncargueApartando(
        db,
        nombreCliente: 'María',
        lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
        usuarioId: usuarioId,
        senaCentavos: 200000,
        sesionCajaId: sesionId,
      );
      await abrirConCaja(tester, sesionId);
      expect(find.text('Entregar y anotar deuda'), findsNothing, reason: 'con seña no se anota deuda');
      await tester.tap(find.text('Cancelar').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Se le devuelven'), findsOneWidget);
      await tester.tap(find.text('Cancelar encargue'));
      await tester.pumpAndSettle();
      expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('DEVOLUCION_SENA'))).get(), hasLength(1));
      expect(find.byKey(const Key('encargues_vacio')), findsOneWidget);
    });

    testWidgets('cancelar con seña y sin caja abierta no cancela: explica que hay que abrir la caja', (tester) async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearEncargueApartando(
        db,
        nombreCliente: 'María',
        lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
        usuarioId: usuarioId,
        senaCentavos: 200000,
        sesionCajaId: sesionId,
      );
      await abrir(tester); // sin sesionCajaId
      await tester.tap(find.text('Cancelar').first);
      await tester.pumpAndSettle();
      expect(find.text('No hay una caja abierta'), findsOneWidget);
      expect(await listarEnarguesPendientes(db), hasLength(1));
    });
  });
}
