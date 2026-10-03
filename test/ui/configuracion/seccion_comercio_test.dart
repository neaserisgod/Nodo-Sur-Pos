import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaConfiguracion(db: db, usuarioId: 1)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Comercio es lo primero de Configuración (grupo Negocio), con el nombre actual', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();

    final nombre = tester.widget<TextField>(_campo('campo_nombre_comercio'));
    expect(nombre.controller!.text, 'Comercio de prueba');
    expect(find.byKey(const Key('campo_encabezado_ticket')), findsOneWidget);
  });

  testWidgets('guardar el nombre y el encabezado del ticket los persiste', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();

    await tester.enterText(_campo('campo_nombre_comercio'), '  Kiosco Del Centro ');
    await tester.enterText(_campo('campo_encabezado_ticket'), 'Kiosco Del Centro\nSan Martín 123\nMendoza');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final fila = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(fila.nombreComercio, 'Kiosco Del Centro');
    expect(fila.encabezadoTicket, 'Kiosco Del Centro\nSan Martín 123\nMendoza');
  });

  testWidgets('el ticket de muestra sigue al nombre que se escribe, sin tener que guardar', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_nombre_comercio'), 'Almacén Norte');
    await tester.pumpAndSettle();
    expect(find.text('Almacén Norte'), findsWidgets);
  });

  testWidgets('dejar el nombre vacío no rompe: queda sin cargar', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_nombre_comercio'), '');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).nombreComercio, '');
  });

  testWidgets('en una base nueva el nombre arranca vacío y el encabezado también', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_campo('campo_nombre_comercio')).controller!.text, '');
    expect(tester.widget<TextField>(_campo('campo_encabezado_ticket')).controller!.text, '');
  });
}
