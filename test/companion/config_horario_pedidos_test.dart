import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_config_agenda_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/turnos.dart';

/// Nodo Gastro (§22): el horario y el alias de las transferencias, sin turnos ni seña. Lo de la seña que hubiera no se toca.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget app(Widget home) => MaterialApp(
        theme: TemaCompanion.claro,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: home,
      );

  testWidgets('guarda el alias sin pedir seña ni turnos, y deja la seña como estaba', (t) async {
    t.view.physicalSize = const Size(390 * 2, 1600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await guardarConfigAgenda(db, const ConfigAgenda(pasoMinutos: 30, sena: ConfigSena(modo: ModoSena.todos, porcentaje: 50)));
    await t.pumpWidget(app(PantallaConfigAgendaNs(db: db, paraPedidos: true)));
    await t.pumpAndSettle();
    expect(find.text('Horario y transferencias'), findsOneWidget);
    expect(find.text('Seña'), findsNothing);
    expect(find.text('Los turnos arrancan cada'), findsNothing);
    await t.enterText(find.byKey(const Key('pedidos_alias')), 'rotiseria.ana');
    await t.dragUntilVisible(find.text('Guardar'), find.byType(ListView), const Offset(0, -300));
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();
    final c = await configAgendaActual(db);
    expect(c.aliasSena, 'rotiseria.ana');
    expect(c.pasoMinutos, 30);
    expect(c.sena.modo, ModoSena.todos);
    expect(c.sena.porcentaje, 50);
    // Que se vaya el aviso de "Horario guardado".
    await t.pump(const Duration(seconds: 10));
  });
}
