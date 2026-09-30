import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/ui/stock_proveedor/pantalla_stock_proveedor.dart';
import 'package:la_plazoleta/ui/tema/colores_escritorio.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, int usuarioId) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaStockProveedor(db: db, usuarioId: usuarioId)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  testWidgets('un producto agotado aparece primero y con el nombre en rojo (Regla 8)', (tester) async {
    await crearProducto(db, nombre: 'Con stock', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
    await crearProducto(db, nombre: 'Agotado', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);

    await _pump(tester, db, usuarioId);

    final nombres = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(nombres.indexOf('Agotado'), lessThan(nombres.indexOf('Con stock')));

    final estiloAgotado = tester.widget<Text>(find.text('Agotado')).style;
    expect(estiloAgotado?.color, coloresEscritorioOscuro.error);
  });

  testWidgets('contar una fila no toca la base hasta "Aplicar ajustes", que deja un movimiento AJUSTE', (tester) async {
    final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);

    await _pump(tester, db, usuarioId);

    final campo = find.descendant(of: find.byType(ListView), matching: find.byType(TextField));
    await tester.enterText(campo.first, '3');
    await tester.pumpAndSettle();
    expect(find.text('−7'), findsOneWidget);
    expect((await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()).stock, 10);

    await tester.tap(find.text('Aplicar ajustes (1)'));
    await tester.pumpAndSettle();

    final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(producto.stock, 3);

    final movimiento =
        await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
    expect(movimiento.tipo, 'AJUSTE');
    expect(movimiento.stockAnterior, 10);
    expect(movimiento.stockPosterior, 3);
  });

  testWidgets('filtrar por proveedor deja solo sus productos', (tester) async {
    final proveedores = await listarProveedores(db);
    final serra = proveedores.firstWhere((p) => p.codigo == 'S');

    await crearProducto(db, nombre: 'De Distribuidora', proveedorId: serra.id, precioCentavos: 1000, usuarioId: usuarioId);
    await crearProducto(db, nombre: 'Suelto', precioCentavos: 1000, usuarioId: usuarioId);

    await _pump(tester, db, usuarioId);
    expect(find.text('Suelto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filtro_proveedor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(serra.nombre).last);
    await tester.pumpAndSettle();

    expect(find.text('De Distribuidora'), findsOneWidget);
    expect(find.text('Suelto'), findsNothing);
  });
}
