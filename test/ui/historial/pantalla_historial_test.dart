import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/historial/pantalla_historial.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, int usuarioId) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaHistorial(db: db, usuarioId: usuarioId)));
  await tester.pumpAndSettle();
  // Arranca en "Ventas" (mock de Historial, 2026-09-26); estos tests son de
  // los cierres.
  await tester.tap(find.text('Cierres de caja'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin días cerrados, avisa que no hay nada todavía', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));

    await _pump(tester, db, usuarioId);

    expect(find.textContaining('Todavía no hay'), findsOneWidget);
  });

  testWidgets('un día con diferencia distinta de cero se ve de un vistazo (color de error)', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
            estado: const Value('CERRADA'),
            diferenciaCentavos: const Value(-500),
          ),
        );

    await _pump(tester, db, usuarioId);

    final texto = tester.widget<Text>(find.byKey(const Key('estado_cierre')));
    final color = (texto.style?.color)!;
    expect(color, Theme.of(tester.element(find.byType(Scaffold))).colorScheme.error);
  });

  testWidgets('dos turnos del mismo día se distinguen por hora y empleado (Bruno, turnos)', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final brunoId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    final anaId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    final hoy = DateTime.now();

    await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: brunoId,
            fondoInicialCentavos: 0,
            estado: const Value('CERRADA'),
            fechaApertura: Value(DateTime(hoy.year, hoy.month, hoy.day, 8, 15)),
          ),
        );
    await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: anaId,
            fondoInicialCentavos: 0,
            estado: const Value('CERRADA'),
            fechaApertura: Value(DateTime(hoy.year, hoy.month, hoy.day, 16, 0)),
          ),
        );

    await _pump(tester, db, brunoId);

    // En la lista, cada turno con su hora y su empleado (el primero también
    // aparece en el detalle de la derecha, por eso `findsWidgets`).
    expect(find.textContaining('08:15'), findsWidgets);
    expect(find.textContaining('16:00'), findsWidgets);
    expect(find.textContaining('Bruno'), findsWidgets);
    expect(find.textContaining('Ana'), findsWidgets);
  });
}
