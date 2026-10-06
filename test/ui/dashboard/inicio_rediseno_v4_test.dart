// Inicio del rediseño v4: sin "Nueva venta" y tres columnas iguales arriba y abajo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  testWidgets('no hay "Nueva venta"; arriba van lo vendido, los indicadores y los más vendidos; abajo tres tarjetas iguales', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
    final db = baseDeTest();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaDashboard(db: db)));
    await tester.pumpAndSettle();

    expect(find.text('Nueva venta'), findsNothing);

    final vendido = tester.getRect(find.text('Vendido hoy'));
    final masVendidos = tester.getRect(find.text('Más vendidos hoy'));
    final comoPagaron = tester.getRect(find.text('Cómo te pagaron'));
    final stockBajo = tester.getRect(find.text('Stock bajo'));
    final pendientes = tester.getRect(find.text('Encargues y deudas'));
    // "Más vendidos" subió a la fila de arriba, junto a lo vendido.
    expect(masVendidos.top, closeTo(vendido.top, 4));
    expect(comoPagaron.top, greaterThan(vendido.bottom));
    // Abajo, tres tarjetas en la misma fila y de igual ancho (sus títulos arrancan a un paso regular).
    expect(stockBajo.top, closeTo(comoPagaron.top, 2));
    expect(pendientes.top, closeTo(comoPagaron.top, 2));
    final paso1 = stockBajo.left - comoPagaron.left;
    final paso2 = pendientes.left - stockBajo.left;
    expect(paso1, closeTo(paso2, 2), reason: 'columnas iguales');
  });
}
