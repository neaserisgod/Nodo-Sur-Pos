// "+ Nuevo proveedor" y "+ Nueva categoría" sin salir del formulario de producto (El dueño, 2026-10-09: independizar el celular),
// sobre la base del celular: lo recién creado queda elegido y el producto se guarda con eso.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_formulario_producto.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/base_para_tests.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Finder campo(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));

  Future<void> esperar(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pumpAndSettle();
  }

  testWidgets('crea un proveedor y una categoría desde el formulario y el producto queda con los dos', (t) async {
    t.view.physicalSize = const Size(430, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    final puerto = PuertoLocal(baseLocalCompanion());
    final proveedores = (await t.runAsync(() => puerto.proveedores()))!;
    final categorias = (await t.runAsync(() => puerto.categorias()))!;
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaFormularioProducto(cliente: puerto, usuarioId: 1, proveedores: proveedores, categorias: categorias),
    ));
    await esperar(t);

    await t.enterText(campo('Nombre'), 'Lavandina 1 L');
    await t.enterText(campo('Precio de venta'), '1500');

    await t.tap(find.text('+ Nuevo proveedor'));
    await esperar(t);
    await t.enterText(campo('Nombre'), 'Química del Sur');
    await t.tap(find.text('Dar de alta'));
    await esperar(t);
    await t.pump(const Duration(seconds: 4));

    await t.tap(find.text('+ Nueva categoría'));
    await esperar(t);
    await t.enterText(find.byType(TextField).last, 'Limpieza');
    await t.tap(find.text('Crear'));
    await esperar(t);

    await t.tap(find.text('Dar de alta'));
    await esperar(t);
    await t.pump(const Duration(seconds: 4));

    final producto = (await t.runAsync(() => db.select(db.productos).get()))!.singleWhere((p) => p.nombre == 'Lavandina 1 L');
    final proveedor = (await t.runAsync(() => db.select(db.proveedores).get()))!.singleWhere((p) => p.nombre == 'Química del Sur');
    final categoria = (await t.runAsync(() => db.select(db.categorias).get()))!.singleWhere((c) => c.nombre == 'Limpieza');
    expect(producto.proveedorId, proveedor.id);
    expect(producto.categoriaId, categoria.id);
  });
}
