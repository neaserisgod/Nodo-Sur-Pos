// Rediseño v4 de Venta: sin título "Vender", buscador con "Pagar proveedor" al lado (Alt+P) y "Varios" a la vista.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  Future<void> abrirVenta(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'QU', nombre: 'Cervecería Quilmes'));
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, navigatorObservers: [routeObserver], home: PantallaVenta(db: db)));
    await tester.pumpAndSettle();
  }

  testWidgets('no hay título "Vender"; sí el botón Pagar proveedor y la pastilla Varios', (tester) async {
    await abrirVenta(tester);
    expect(find.text('Vender'), findsNothing);
    expect(find.byKey(const Key('boton_pagar_proveedor')), findsOneWidget);
    expect(find.byKey(const Key('pildora_varios')), findsOneWidget);
    expect(find.byKey(const Key('boton_caja')), findsOneWidget);
  });

  testWidgets('el botón Pagar proveedor abre el pago rápido', (tester) async {
    await abrirVenta(tester);
    await tester.tap(find.byKey(const Key('boton_pagar_proveedor')));
    await tester.pumpAndSettle();
    expect(find.text('Pagar proveedor'), findsWidgets);
    expect(find.byKey(const Key('pago_rapido_busqueda')), findsOneWidget);
    expect(find.text('Cervecería Quilmes'), findsOneWidget);
  });

  testWidgets('Alt+P abre el pago rápido desde cualquier lado de la pantalla', (tester) async {
    await abrirVenta(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pago_rapido_busqueda')), findsOneWidget);
  });

  testWidgets('la pastilla Varios abre el diálogo de monto suelto', (tester) async {
    await abrirVenta(tester);
    await tester.tap(find.byKey(const Key('pildora_varios')));
    await tester.pumpAndSettle();
    expect(find.text('Agregar al ticket'), findsOneWidget);
  });
}
