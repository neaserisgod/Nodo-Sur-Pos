import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/carga_historica/pantalla_carga_historica.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, int usuarioId) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaCargaHistorica(db: db, usuarioId: usuarioId)),
  );
  await tester.pumpAndSettle();
}

Future<void> _elegirFecha(WidgetTester tester, String fecha) async {
  await tester.enterText(find.byKey(const Key('campo_fecha_carga_historica')), fecha);
  await tester.tap(find.text('Empezar a cargar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'buscar un producto, agregarlo, elegir efectivo, sumarlo a la tanda y guardar el día',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(500000), stock: const Value(10)),
        );

    await _pump(tester, db, usuarioId);
    await _elegirFecha(tester, '20/08/2026');

    expect(find.textContaining('Cargando el 20/08/2026'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('campo_busqueda_carga_historica')),
      'Fernet',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fernet').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Efectivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar venta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('total \$5.000'), findsOneWidget);

    await tester.tap(find.textContaining('Guardar día'));
    await tester.pumpAndSettle();

    final ventas = await db.select(db.ventas).get();
    expect(ventas, hasLength(1));
    expect(ventas.single.totalCentavos, 500000);
    final sesion = await db.select(db.sesionesDeCaja).getSingle();
    expect(sesion.estado, 'CERRADA');
    expect(sesion.fechaApertura, DateTime(2026, 8, 20, 12));

    final producto = await (db.select(db.productos)..where((p) => p.nombre.equals('Fernet'))).getSingle();
    expect(producto.stock, 10); // no se tocó
  });

  testWidgets('guardar sin ninguna venta en la tanda deja un error visible', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));

    await _pump(tester, db, usuarioId);
    await _elegirFecha(tester, '20/08/2026');

    await tester.tap(find.textContaining('Guardar día'));
    await tester.pumpAndSettle();

    expect(find.text('Agregá al menos una venta'), findsOneWidget);
  });
}
