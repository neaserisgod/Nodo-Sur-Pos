import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantalla_promos.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Promos en el celular (El dueño, 2026-10-07): lo mismo que la PC, sobre la base del celular.
void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest(null);
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    for (final n in ['Yerba', 'Galletitas']) {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: n, precioCentavos: const Value(300000), costoCentavos: const Value(200000), stock: const Value(10)),
          );
    }
  });
  tearDown(() => db.close());

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaPromos(db: db, usuarioId: usuario)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  testWidgets('sin promos lo explica; arma una con dos artículos, muestra el precio y la guarda', (tester) async {
    await abrir(tester);
    expect(find.textContaining('Todavía no armaste ninguna'), findsOneWidget);

    await tester.tap(find.text('Nueva promo'));
    await esperar(tester);
    await tester.enterText(find.byType(TextField).first, 'Merienda');
    for (final n in ['Yerba', 'Galle']) {
      await tester.enterText(find.byType(TextField).at(1), n);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(' · \$'));
      await tester.pumpAndSettle();
    }
    // Costo $4.000 con 30 % de ganancia sobre el precio → $5.714 → $5.800 a la centena; los sueltos salen $6.000.
    expect(find.text('\$\u00A05.800'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar promo'));
    await tester.tap(find.text('Guardar promo'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6)); // el aviso se va solo

    final promos = await listarPromos(db);
    expect(promos.single.promo.nombre, 'Merienda');
    expect(promos.single.promo.precioCentavos, 580000);
    expect(promos.single.promo.globalId, isNotNull, reason: 'viaja a la PC');
    expect(find.text('Merienda'), findsOneWidget);
  });

  testWidgets('desactivar la deja fuera de la venta y lo dice', (tester) async {
    final ids = [for (final p in await db.select(db.productos).get()) if (p.nombre == 'Yerba' || p.nombre == 'Galletitas') p.id];
    await guardarPromo(db, nombre: 'Merienda', articulos: [for (final id in ids) (productoId: id, cantidad: 1)], gananciaBp: 3000, usuarioId: usuario);
    await abrir(tester);
    await tester.tap(find.text('Desactivar'));
    await esperar(tester);
    expect(find.textContaining('Desactivada'), findsOneWidget);
    expect((await listarPromos(db)).single.promo.activo, isFalse);
  });

  testWidgets('sugerencias sin ventas: explica qué hace falta', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('Sugerir promos'));
    await esperar(tester);
    expect(find.textContaining('Todavía no hay nada para sugerir'), findsOneWidget);
  });
}
