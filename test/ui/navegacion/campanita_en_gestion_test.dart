// La campanita (rediseño v4) está en la navbar de todas las pantallas, no solo en Venta; fuera de Venta no ofrece el arqueo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  testWidgets('Inicio tiene campanita; abierta dice "Sin novedades" y no ofrece "Hacer arqueo"', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    await tester.tap(find.byTooltip('Notificaciones'));
    await tester.pumpAndSettle();
    expect(find.text('Sin novedades por ahora'), findsOneWidget);
    expect(find.text('Hacer arqueo'), findsNothing);
  });
}
