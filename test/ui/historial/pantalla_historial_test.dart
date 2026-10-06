import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/historial/pantalla_historial.dart';
import 'package:la_plazoleta/ui/kit/kit.dart';
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
  await tester.tap(find.text('Cierres'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Cargar día histórico" solo se ofrece con el módulo Carga histórica prendido', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);

    await _pump(tester, db, usuarioId);
    expect(find.text('Cargar día histórico'), findsOneWidget);

    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.cargaHistorica, activo: false);
    await tester.pump();
    expect(find.text('Cargar día histórico'), findsNothing);
    expect(find.text('Cierres'), findsOneWidget);
  });

  testWidgets('sin días cerrados, avisa que no hay nada todavía', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));

    await _pump(tester, db, usuarioId);

    expect(find.textContaining('Todavía no hay'), findsOneWidget);
  });

  testWidgets('un día con diferencia distinta de cero se ve de un vistazo (color de error)', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
            estado: const Value('CERRADA'),
            diferenciaCentavos: const Value(-500),
          ),
        );

    await _pump(tester, db, usuarioId);

    // La etiqueta del estado va en rojo (tono "b" del mock) cuando faltó plata.
    final etiqueta = tester.widget<Etiqueta>(find.byKey(const Key('estado_cierre')));
    expect(etiqueta.tono, TonoMock.b);
    expect(etiqueta.texto, r'Faltaron $ 5');
  });

  testWidgets('dos turnos del mismo día se distinguen por hora y empleado (Dueño, turnos)', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final brunoId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
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
    expect(find.textContaining('Dueño'), findsWidgets);
    expect(find.textContaining('Ana'), findsWidgets);
  });
}
