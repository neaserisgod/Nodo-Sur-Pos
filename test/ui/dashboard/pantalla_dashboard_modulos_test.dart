// El Inicio sigue a los módulos: sin Fiado no hay tarjeta de fiados y encargues; sin Equilibrio no hay vista mensual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('con todo activo: tarjeta de fiados y encargues, y vista "Este mes"', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    expect(find.text('Encargues y deudas'), findsOneWidget);
    expect(find.text('Este mes'), findsOneWidget);
  });

  testWidgets('sin el módulo Fiado desaparece la tarjeta, sin tocar el resto', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.fiado, activo: false);
    await tester.pumpAndSettle();
    expect(find.text('Encargues y deudas'), findsNothing);
    expect(find.text('Stock bajo'), findsWidgets);
    expect(find.text('Este mes'), findsOneWidget);
  });

  testWidgets('sin el módulo Equilibrio no hay vista mensual, ni estando parado en ella', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    await tester.tap(find.text('Este mes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Este mes ·'), findsOneWidget);

    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.equilibrio, activo: false);
    await tester.pumpAndSettle();
    expect(find.text('Este mes'), findsNothing);
    expect(find.textContaining('Este mes ·'), findsNothing);
    expect(find.text('Encargues y deudas'), findsOneWidget);
  });
}
