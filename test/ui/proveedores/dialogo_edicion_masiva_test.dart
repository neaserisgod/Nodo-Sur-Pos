// Bug real (El dueño, revisión de "errores humanos evitables"): antes, Enter
// en el campo de porcentaje/monto de la edición masiva aplicaba el cambio
// DIRECTO a todos los productos marcados, sin ningún paso de revisión ni
// techo de sanidad — escribir "500" en vez de "50" (un dedo de más, o el
// punto decimal que faltó) multiplicaba precios x5 en todo lo marcado, sin
// aviso y sin un botón de deshacer. Estos tests cubren el paso de revisión
// agregado: "Revisar" (o Enter) nunca escribe nada en la base, solo
// "Sí, aplicar" en el segundo paso lo hace — y un ajuste de 100% o más
// muestra una advertencia explícita antes de ese click final.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/proveedores/dialogo_edicion_masiva.dart';
import 'package:la_plazoleta/ui/proveedores/proveedores_controlador.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _abrir(WidgetTester tester, ProveedoresControlador controlador) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => mostrarDialogoEdicionMasiva(context, controlador: controlador),
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
  late int productoId;
  late ProveedoresControlador controlador;

  setUp(() async {
    db = baseDeTest();
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    productoId = await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            nombre: 'Coca-Cola 500ml',
            precioCentavos: const Value(112000),
            stock: const Value(20),
          ),
        );
    controlador = ProveedoresControlador(db, usuarioId: usuarioId, sesionCajaId: null);
    await controlador.cargarTodo();
    controlador.alternarSeleccionMasiva(productoId);
  });
  tearDown(() => db.close());

  Future<int?> precioActual() async {
    final fila = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    return fila.precioCentavos;
  }

  testWidgets('Enter en el campo de porcentaje no aplica directo — pasa a revisar', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(await precioActual(), 112000); // sin tocar todavía
    expect(find.text('Sumar 50% al precio de venta'), findsOneWidget);
    expect(find.text('Sí, aplicar'), findsOneWidget);
  });

  testWidgets('"Revisar" tampoco aplica nada — solo muestra el resumen', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(await precioActual(), 112000);
    expect(find.text('Sumar 50% al precio de venta'), findsOneWidget);
  });

  testWidgets('un aumento de 100% o más muestra la advertencia de "un dígito de más"', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('más del doble del valor actual'), findsOneWidget);
  });

  testWidgets('un porcentaje normal (<100%) no muestra ninguna advertencia', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '20');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Revisá que no'), findsNothing);
  });

  testWidgets('restar 100% o más avisa que el precio queda en \$0', (tester) async {
    await _abrir(tester, controlador);

    await tester.tap(find.text('Restar %'));
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('deja el precio en \$0'), findsOneWidget);
  });

  testWidgets('"Volver" regresa al formulario sin aplicar nada', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Editar 1 productos'), findsOneWidget);
    expect(await precioActual(), 112000);
  });

  testWidgets('recién "Sí, aplicar" escribe el cambio en la base', (tester) async {
    await _abrir(tester, controlador);

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.tap(find.text('Revisar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sí, aplicar'));
    await tester.pumpAndSettle();

    expect(await precioActual(), 168000); // 112000 + 50%
  });
}
