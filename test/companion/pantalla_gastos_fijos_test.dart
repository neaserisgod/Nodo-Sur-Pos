// Gastos fijos en el celular (El dueño, 2026-10-09: independizar el celular): alta con monto y vencimiento, y corregir el monto.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_gastos_fijos.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('paga un fijo desde el celular: queda como gasto del mes y la fila dice Pagado', (t) async {
    t.view.physicalSize = const Size(430, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final usuario = (await db.select(db.usuarios).get()).first;
    SharedPreferences.setMockInitialValues({'companion_usuario_id': usuario.id, 'companion_usuario_nombre': usuario.nombre});
    final id = await crearConcepto(db, 'Seguro del local');
    await cargarMontoDelMes(db, gastoFijoId: id, mesAnio: '2026-10', montoCentavos: 3000000);

    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaGastosFijos(db: db, ahora: DateTime(2026, 10, 9))));
    await esperar(t);

    final fila = find.ancestor(of: find.text('Seguro del local'), matching: find.byType(Row)).first;
    final pagar = find.descendant(of: fila, matching: find.text('Pagar'));
    // Sin caja abierta no se anota nada.
    await t.tap(pagar);
    await esperar(t);
    await t.tap(find.text('Anotar pago'));
    await esperar(t);
    expect(find.textContaining('No hay caja abierta'), findsOneWidget);
    expect(await pagadoPorConceptoDelMes(db, '2026-10'), isEmpty);

    await t.runAsync(() => abrirSesion(db, usuarioId: usuario.id, fondoInicialCentavos: 0));
    await t.tap(find.text('Anotar pago'));
    await esperar(t);

    expect(await pagadoPorConceptoDelMes(db, '2026-10'), {id: 3000000});
    final mov = (await db.select(db.movimientosDeCaja).get()).single;
    expect(mov.tipo, 'GASTO');
    expect(mov.medioPagoId, isNull, reason: 'del cajón');
    final filaDespues = find.ancestor(of: find.text('Seguro del local'), matching: find.byType(Row)).first;
    expect(find.descendant(of: filaDespues, matching: find.textContaining('Pagado')), findsOneWidget);
    expect(find.descendant(of: filaDespues, matching: find.text('Pagar')), findsNothing);
    await t.pumpAndSettle(const Duration(seconds: 10)); // que se vaya el aviso "Pago anotado"
  });
}
