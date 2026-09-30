// El aviso de primer arranque: "Datos de tu comercio". Aparece solo si el comercio todavía no cargó su nombre.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('una base nueva pide los datos del comercio al abrir', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    expect(find.text('Datos de tu comercio'), findsOneWidget);
    expect(find.byKey(const Key('campo_nombre_comercio')), findsOneWidget);
  });

  testWidgets('guardar deja el nombre y, si no se escribió un encabezado, el ticket lleva el nombre', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.enterText(_campo('campo_nombre_comercio'), 'Kiosco Del Centro');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final fila = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(fila.nombreComercio, 'Kiosco Del Centro');
    expect(fila.encabezadoTicket, 'Kiosco Del Centro');
    expect(find.text('Datos de tu comercio'), findsNothing);
  });

  testWidgets('se puede guardar con un encabezado de ticket de varias líneas', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.enterText(_campo('campo_nombre_comercio'), 'Almacén Norte');
    await tester.enterText(_campo('campo_encabezado_ticket'), 'Almacén Norte\nRuta 40 km 10');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).encabezadoTicket, 'Almacén Norte\nRuta 40 km 10');
  });

  testWidgets('guardar sin nombre no cierra el aviso ni guarda nada', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Datos de tu comercio'), findsOneWidget);
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).nombreComercio, '');
  });

  testWidgets('"Más tarde" cierra el aviso sin guardar y no vuelve a preguntar mientras la app siga abierta', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();
    expect(find.text('Datos de tu comercio'), findsNothing);
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).nombreComercio, '');
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Datos de tu comercio'), findsNothing);
  });

  testWidgets('un comercio que ya cargó su nombre no ve el aviso', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    expect(find.text('Datos de tu comercio'), findsNothing);
  });
}
