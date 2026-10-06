// Asistente (Ctrl+K), rediseño v4: buscador de acciones, pantallas y productos. Sin IA ni red.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/asistente.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  group('filtrarItemsAsistente', () {
    final items = [
      ItemAsistente(grupo: 'Acciones', titulo: 'Pagar proveedor', icono: Icons.add, palabras: 'deuda pago', alElegir: () {}),
      ItemAsistente(grupo: 'Acciones', titulo: 'Hacer arqueo', icono: Icons.add, palabras: 'contar caja', alElegir: () {}),
      ItemAsistente(grupo: 'Ir a', titulo: 'Historial', icono: Icons.add, alElegir: () {}),
    ];

    test('sin texto devuelve todo', () => expect(filtrarItemsAsistente(items, '  '), items));

    test('ignora mayúsculas y acentos y mira también las palabras extra', () {
      expect(filtrarItemsAsistente(items, 'ARQUEO').map((i) => i.titulo), ['Hacer arqueo']);
      expect(filtrarItemsAsistente(items, 'contar').map((i) => i.titulo), ['Hacer arqueo']);
      expect(filtrarItemsAsistente(items, 'histórial'.replaceAll('ó', 'o')).map((i) => i.titulo), ['Historial']);
    });

    test('varias palabras: tienen que estar todas', () {
      expect(filtrarItemsAsistente(items, 'pagar prov').map((i) => i.titulo), ['Pagar proveedor']);
      expect(filtrarItemsAsistente(items, 'pagar arqueo'), isEmpty);
    });
  });

  Future<void> ctrlK(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('en Inicio: Ctrl+K abre el asistente con las acciones de la caja abierta', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Coca-Cola 500ml', precioCentavos: const Value(100000), stock: const Value(10)));
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    expect(find.byKey(const Key('asistente_campo')), findsOneWidget);
    expect(find.text('Pagar proveedor'), findsOneWidget);
    expect(find.text('Gasto rápido'), findsOneWidget);
    expect(find.text('Cerrar caja'), findsOneWidget);

    // Escribir filtra, incluso productos del catálogo.
    await tester.enterText(find.byKey(const Key('asistente_campo')), 'coca');
    await tester.pump();
    expect(find.text('Coca-Cola 500ml'), findsOneWidget);
    expect(find.text('Pagar proveedor'), findsNothing);

    // Esc cierra.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asistente_campo')), findsNothing);
  });

  testWidgets('elegir "Pagar proveedor" abre el pago rápido', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_asistente')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('asistente_campo')), 'pagar');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter elige la primera
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pago_rapido_busqueda')), findsOneWidget);
  });

  testWidgets('sin caja abierta ofrece "Abrir caja" y nada más de caja', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)));
    await tester.pumpAndSettle();
    await ctrlK(tester);
    expect(find.text('Abrir caja'), findsOneWidget);
    expect(find.text('Pagar proveedor'), findsNothing);
  });

  testWidgets('en Venta: Ctrl+K y un producto lo deja escrito en el campo único', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Yerba Taragüí 1 kg', precioCentavos: const Value(460000), stock: const Value(10)));
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaVenta(db: db)));
    await tester.pumpAndSettle();

    await ctrlK(tester);
    await tester.enterText(find.byKey(const Key('asistente_campo')), 'yerba');
    await tester.pump();
    await tester.tap(find.byKey(const Key('asistente_Productos_Yerba Taragüí 1 kg')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asistente_campo')), findsNothing);
    final campo = tester.widget<TextField>(find.byType(TextField).first);
    expect(campo.controller!.text, 'Yerba Taragüí 1 kg');
  });
}
