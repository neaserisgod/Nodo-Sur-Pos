// Bug real (El dueño, revisión de "errores humanos evitables"): "Aplicar"
// escribía DIRECTO sobre todos los productos marcados, sin ningún resumen
// ni techo de sanidad en el porcentaje — mismo problema que ya tenía
// `dialogo_edicion_masiva.dart` del escritorio (Regla 3: mismo arreglo acá).
// Estos tests cubren el paso de revisión: "Revisar" nunca escribe nada en
// la base, solo "Sí, aplicar" en el segundo paso lo hace — y un ajuste de
// 100% o más muestra una advertencia explícita antes de ese click final.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/hoja_edicion_masiva.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/hoja_vidrio.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import '../helpers/base_para_tests.dart';

Future<void> _abrir(
  WidgetTester tester,
  PuertoLocal cliente,
  int usuarioId,
  List<int> productoIds,
) async {
  // El viewport de test por defecto (800×600) es más chico que un celular
  // real parado, y la hoja de edición masiva no entra — los botones del
  // pie quedan fuera del área tocable (TRAMPAS.md: "el viewport de test
  // por defecto no representa la resolución real").
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => mostrarHojaVidrio<bool>(
            context,
            builder: (_) => HojaEdicionMasiva.porProveedor(
              cliente: cliente,
              usuarioId: usuarioId,
              productoIds: productoIds,
              nombreProveedor: 'Distribuidora',
            ),
          ),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late PuertoLocal cliente;
  late int usuarioId;
  late int productoId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    productoId = await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            nombre: 'Coca-Cola 500ml',
            precioCentavos: const Value(112000),
            stock: const Value(20),
          ),
        );
    cliente = PuertoLocal(db);
  });
  tearDown(() => db.close());

  Future<int?> precioActual() async {
    final fila = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    return fila.precioCentavos;
  }

  testWidgets('"Revisar" no aplica nada todavía — solo muestra el resumen', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    // `_accion` arranca en "Recibí un pedido" (stock) — el primer chip del
    // `Set` de acciones de `.porProveedor` — hay que elegir precio primero.
    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(await precioActual(), 112000);
    expect(find.text('Sumar 50% al precio de venta'), findsOneWidget);
    expect(find.text('Sí, aplicar'), findsOneWidget);
  });

  testWidgets('un aumento de 100% o más muestra la advertencia de "un dígito de más"', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('más del doble del valor actual'), findsOneWidget);
  });

  testWidgets('un porcentaje normal (<100%) no muestra ninguna advertencia', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Revisá que no'), findsNothing);
  });

  testWidgets('restar 100% o más avisa que el precio queda en \$0', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restar %'));
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('deja el precio en \$0'), findsOneWidget);
  });

  testWidgets('"Volver" regresa al formulario sin aplicar nada', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Productos de Distribuidora'), findsOneWidget);
    expect(await precioActual(), 112000);
  });

  testWidgets('recién "Sí, aplicar" escribe el cambio en la base', (tester) async {
    await _abrir(tester, cliente, usuarioId, [productoId]);

    await tester.tap(find.text('Subió el precio'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sí, aplicar'));
    await tester.pumpAndSettle();

    expect(await precioActual(), 168000); // 112000 + 50%
  });
}
