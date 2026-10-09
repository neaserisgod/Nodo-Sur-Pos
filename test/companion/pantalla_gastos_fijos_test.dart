// Gastos fijos en el celular (El dueño, 2026-10-09: independizar el celular): alta con monto y vencimiento, y corregir el monto.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_gastos_fijos.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  Finder campo(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));

  Future<void> esperar(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pumpAndSettle();
  }

  testWidgets('da de alta un fijo con su monto y vencimiento, y después corrige el monto', (t) async {
    t.view.physicalSize = const Size(430, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaGastosFijos(db: db, ahora: DateTime(2026, 10, 9))));
    await esperar(t);

    await t.tap(find.text('+ Nuevo'));
    await esperar(t);
    await t.enterText(campo('Nombre'), 'Alquiler del local');
    await t.enterText(campo('Monto de este mes'), '450000');
    await t.enterText(campo('Día en que vence (opcional)'), '10');
    await t.tap(find.text('Dar de alta'));
    await esperar(t);

    final fijo = (await db.select(db.gastosFijos).get()).singleWhere((g) => g.nombre == 'Alquiler del local');
    expect(fijo.diaVencimiento, 10);
    expect(fijo.globalId, isNotNull, reason: 'viaja a la PC');
    expect((await fijosDelMes(db, '2026-10')).conceptos.singleWhere((c) => c.concepto.id == fijo.id).montoCentavos, 45000000);
    expect(find.text('Alquiler del local'), findsOneWidget);

    await t.tap(find.text('Alquiler del local'));
    await esperar(t);
    await t.enterText(campo('Monto de este mes'), '480000');
    await t.tap(find.text('Guardar'));
    await esperar(t);
    expect((await fijosDelMes(db, '2026-10')).conceptos.singleWhere((c) => c.concepto.id == fijo.id).montoCentavos, 48000000);
  });
}
