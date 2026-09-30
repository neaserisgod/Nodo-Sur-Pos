// Buscador contextual (2026-09-28, el dueño: "que busque según la pantalla que
// estemos"): el campo de arriba filtra lo de cada pantalla en vez de buscar
// productos para mandar a Venta.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/comun/lista_maestra.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/proveedores/detalle_proveedor.dart';
import 'package:la_plazoleta/ui/proveedores/lista_proveedores.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, home: pantalla));
  await tester.pumpAndSettle();
}

Finder get _buscador => find.byKey(const Key('busqueda_contextual'));

void main() {
  testWidgets('en Proveedores busca productos y deja en la lista solo los proveedores que los tienen', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final serra = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle()).id;
    final arcor = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('A'))).getSingle()).id;
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Coca-Cola 500ml', proveedorId: Value(serra)));
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Alfajor Arcor', proveedorId: Value(arcor)));

    await _pump(tester, PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null));
    expect(find.text('Coca-Cola 500ml'), findsOneWidget);
    expect(find.text('Alfajor Arcor'), findsOneWidget);

    // Sin acentos ni mayúsculas, como el buscador de Venta.
    await tester.enterText(_buscador, 'alfajor');
    await tester.pumpAndSettle();

    final detalle = find.byType(DetalleProveedor);
    expect(find.descendant(of: detalle, matching: find.text('Alfajor Arcor')), findsOneWidget);
    expect(find.descendant(of: detalle, matching: find.text('Coca-Cola 500ml')), findsNothing);
    final lista = find.byType(ListaProveedores);
    expect(find.descendant(of: lista, matching: find.text('Arcor')), findsOneWidget);
    expect(find.descendant(of: lista, matching: find.text('Distribuidora')), findsNothing);

    // Esc borra el filtro.
    await tester.tap(_buscador);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Coca-Cola 500ml'), findsOneWidget);
  });

  testWidgets('en Configuración busca ajustes por palabra clave y abre la única sección que coincide', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));

    await _pump(tester, PantallaConfiguracion(db: db, usuarioId: usuarioId));
    await tester.enterText(_buscador, 'fondo');
    await tester.pumpAndSettle();

    final lista = find.byType(ListaMaestra);
    expect(find.descendant(of: lista, matching: find.text('Caja y redondeo')), findsOneWidget);
    expect(find.descendant(of: lista, matching: find.text('Usuarios')), findsNothing);
    // Se abrió sola: se ve el campo de esa sección.
    expect(find.textContaining('Fondo fijo del cajón'), findsOneWidget);
  });
}
