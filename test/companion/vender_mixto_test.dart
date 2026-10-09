// Mixto en el celular (El dueño, 2026-10-09): una parte en efectivo y el resto por Mercado Pago, sin la PC.
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('mixto a mano: se escribe el efectivo, se ve el resto y la venta queda con los dos pagos', (t) async {
    final cargador = FontLoader('Figtree');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
    }
    await cargador.load();
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    final servicio = PuertoLocal(baseLocalCompanion());
    final cocaId = (await t.runAsync(
      () => db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: const Value(20)),
      ),
    ))!;
    await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0));
    final carrito = <LineaVenta>[
      LineaVentaPorUnidad(productoId: '$cocaId', nombreProducto: 'Coca-Cola', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 112000),
    ];
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(
          controlador: ControladorFalsoNs(),
          version: 0,
          child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito)),
        ),
      ),
    );
    await esperar(t);

    await t.tap(find.text('Cobrar'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await esperar(t);
    final mixto = find.text('Mixto: efectivo + Mercado Pago');
    await t.ensureVisible(mixto);
    await t.tap(mixto);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await esperar(t);

    // $1.120 redondea a $1.200 con efectivo de por medio: $500 en efectivo, $700 por Mercado Pago.
    await t.enterText(find.byType(TextField).last, '500');
    await esperar(t);
    expect(find.text('El resto por Mercado Pago'), findsOneWidget);
    expect(find.textContaining('700'), findsWidgets);

    final aMano = find.text('Cobrar a mano (sin terminal)');
    await t.dragUntilVisible(aMano, find.byType(ListView).last, const Offset(0, -200));
    await esperar(t);
    await t.tap(aMano);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await esperar(t);

    // Sin pantalla de "Venta cobrada": vuelve a una venta nueva con la tarjeta de la que se cobró.
    expect(find.textContaining('Cobrado'), findsOneWidget);
    expect(find.textContaining('Efectivo \$\u00A0500 + MP \$\u00A0700'), findsOneWidget);
    final pagos = (await t.runAsync(() => db.select(db.pagos).get()))!;
    expect(pagos.map((p) => p.montoCentavos).toList()..sort(), [50000, 70000]);
  });

  testWidgets('cobrar en efectivo vuelve directo a una venta nueva: el vuelto queda arriba hasta el próximo producto '
      '(El dueño, 2026-10-09: "siento que hay una pantalla extra")', (t) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    final servicio = PuertoLocal(baseLocalCompanion());
    final cocaId = (await t.runAsync(
      () => db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(120000), stock: const Value(20))),
    ))!;
    await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0));
    final carrito = <LineaVenta>[
      LineaVentaPorUnidad(productoId: '$cocaId', nombreProducto: 'Coca-Cola', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 120000),
    ];
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(controlador: ControladorFalsoNs(), version: 0, child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito))),
      ),
    );
    await esperar(t);

    await t.tap(find.text('Cobrar'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await esperar(t);
    await t.tap(find.text('\$\u00A02.000')); // paga con $2.000
    await esperar(t);
    await t.tap(find.textContaining('Confirmar cobro'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await esperar(t);

    expect(find.text('Venta cobrada'), findsNothing);
    expect(find.text('Cobrado \$\u00A01.200'), findsOneWidget);
    expect(find.text('Dar de vuelto \$\u00A0800'), findsOneWidget);
    expect(carrito, isEmpty);
    final campo = find.byType(TextField).first;
    final editable = t.widget<EditableText>(find.descendant(of: campo, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue, reason: 'el buscador queda listo para la próxima venta');

    // Al agregar el primer producto de la siguiente, la tarjeta se va sola.
    await t.enterText(campo, 'coca');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await esperar(t);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await esperar(t);
    expect(carrito, hasLength(1));
    expect(find.textContaining('Dar de vuelto'), findsNothing);
  });
}

