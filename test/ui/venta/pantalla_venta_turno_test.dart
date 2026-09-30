// Cambio de turno (El dueño, sesión del 31/08/2026): un turno es una sesión
// completa, así que después de cerrar mid-día tiene que poder abrirse una
// hoja nueva sin reiniciar la app — el callejón sin salida que reemplaza
// esto ("Cerrá la aplicación...") nunca tuvo cobertura.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // El viewport de test por defecto (800×600) es más chico que el piso real
  // de la app (1366×768 desde la fase 13) — se fija acá, mismo criterio que
  // el resto de los tests de esta pantalla (ver TRAMPAS.md).
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: PantallaVenta(db: db)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  testWidgets('sin sesión abierta, muestra "Abrir caja" en vez de pedir reiniciar la app', (tester) async {
    await _pump(tester, db);

    expect(find.text('Caja cerrada.'), findsOneWidget);
    expect(find.text('Abrir caja'), findsOneWidget);
    expect(find.textContaining('Cerrá la aplicación'), findsNothing);
  });

  testWidgets('tocar "Abrir caja" abre una hoja nueva y vuelve a vender, sin reiniciar la app', (tester) async {
    await _pump(tester, db);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir caja'));
    await tester.pumpAndSettle();

    // El diálogo de apertura ya sembró un usuario (fase 3, Regla 18) — se
    // elige directo y se confirma con el botón del diálogo, no el de atrás.
    await tester.tap(find.descendant(
      of: find.byType(Dialog),
      matching: find.widgetWithText(ElevatedButton, 'Abrir caja'),
    ));
    await tester.pumpAndSettle();

    // La pantalla de venta vuelve a estar operativa: el campo único de
    // búsqueda está de nuevo en el árbol.
    expect(find.text('Caja cerrada.'), findsNothing);
    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.estado.equals('ABIERTA'))).getSingle();
    expect(sesion, isNotNull);
  });
}
