import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

import '../../capturas/capturador.dart';

/// Creador de promos (Bruno, 2026-09-29).
void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    for (final (nombre, costo, precio) in [('Yerba Taragüí', 100000, 140000), ('Galletitas Terrabusi', 50000, 90000)]) {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: nombre,
              costoCentavos: Value(costo),
              precioCentavos: Value(precio),
              stock: const Value(10),
            ),
          );
    }
    await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro',
            tipoCigarrillo: const Value('atado'),
            costoCentavos: const Value(400000),
            precioCentavos: const Value(500000),
            stock: const Value(10),
          ),
        );
  });
  tearDown(() => db.close());

  testWidgets('armar una promo: se calcula el precio, con tope en la lista, y se guarda', (tester) async {
    final llave = await montarPantallaParaCaptura(
      tester,
      pantalla: PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null),
      tema: TemaPlazoleta.claro,
    );
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no armaste ninguna'), findsOneWidget);

    await tester.tap(find.text('Nueva promo').last);
    await tester.pumpAndSettle();
    expect(find.text('Elegí al menos dos artículos para ver el precio.'), findsOneWidget);

    await tester.enterText(find.descendant(of: find.byKey(const Key('campo_nombre_promo')), matching: find.byType(TextField)), 'Merienda');
    final buscar = find.descendant(of: find.byKey(const Key('campo_buscar_articulo_promo')), matching: find.byType(TextField));

    // Un cigarrillo no aparece como opción.
    await tester.enterText(buscar, 'marl');
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin coincidencias'), findsOneWidget);

    await tester.enterText(buscar, 'yerba');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yerba Taragüí').last);
    await tester.pumpAndSettle();
    await tester.enterText(buscar, 'galle');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galletitas Terrabusi').last);
    await tester.pumpAndSettle();

    // 30%: costo 1.500 → 1.950 → 2.000 (sueltos 2.300).
    expect(find.text(r'$2.000'), findsWidgets);
    expect(find.textContaining('Costo + 30%'), findsOneWidget);
    await guardarCaptura(tester, llave, 'proveedores-promo-creador');

    // 100%: pediría 3.000 pero la lista suma 2.300 → tope.
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    expect(find.text(r'$2.300'), findsWidgets);
    expect(find.textContaining('Tope'), findsOneWidget);
    await tester.tap(find.text('30%'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar promo'));
    await tester.pumpAndSettle();

    final promos = await tester.runAsync(() => listarPromos(db));
    expect(promos!.single.promo.nombre, 'Merienda');
    expect(promos.single.promo.precioCentavos, 200000);
    expect(find.text('Merienda'), findsOneWidget); // ya en la lista
  });
}
