// Las pruebas de accesibilidad de Flutter (docs.flutter.dev/ui/accessibility/accessibility-testing) sobre la pantalla de Venta
// con un producto en el carrito: tamaño táctil, etiquetas y contraste. Mide; el resultado dice qué falta arreglar.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../helpers/base_para_tests.dart';

Future<void> _pantalla(WidgetTester tester, Brightness brillo) async {
  final db = baseDeTest();
  addTearDown(db.close);
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  await db.into(db.productos).insert(ProductosCompanion.insert(
        nombre: 'Coca-Cola 500ml',
        precioCentavos: const Value(112000),
        stock: const Value(20),
      ));
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: brillo == Brightness.dark ? TemaPlazoleta.oscuro : TemaPlazoleta.claro,
    navigatorObservers: [routeObserver],
    home: PantallaVenta(db: db),
  ));
  await tester.pumpAndSettle();
  // Agrega el producto como lo haría el cajero: escribe y Enter.
  await tester.enterText(find.byType(TextField).first, 'coca');
  await tester.pumpAndSettle();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  for (final brillo in [Brightness.light, Brightness.dark]) {
    final nombre = brillo == Brightness.light ? 'claro' : 'oscuro';
    group('Venta, tema $nombre', () {
      testWidgets('objetivos táctiles de 48 dp (Android)', (tester) async {
        final h = tester.ensureSemantics();
        await _pantalla(tester, brillo);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        h.dispose();
      });

      testWidgets('todo lo que se toca tiene etiqueta', (tester) async {
        final h = tester.ensureSemantics();
        await _pantalla(tester, brillo);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });

      testWidgets('contraste del texto', (tester) async {
        final h = tester.ensureSemantics();
        await _pantalla(tester, brillo);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });
    });
  }
}
