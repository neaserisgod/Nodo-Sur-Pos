// Vender del mock (lote 1): descuento libre (monto o porcentaje) y cantidad exacta con un toque.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late List<LineaVenta> carrito;

  Future<void> abrir(WidgetTester t) async {
    final cargador = FontLoader('Figtree');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
    }
    await cargador.load();
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    carrito = [
      const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata 473 ml', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
      const LineaVentaPesable(productoId: 'b', nombreProducto: 'Jamón cocido', proveedorId: null, gramos: 250, precioPorKiloCentavos: 1460000),
    ];
    final db = await t.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    final servicio = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 2000000));
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(controlador: ControladorFalsoNs(), version: 0, child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito))),
      ),
    );
    await esperar(t);
  }

  testWidgets('descuento por porcentaje: el total baja y el chip muestra cuánto', (t) async {
    await abrir(t);
    expect(find.text('Descuento'), findsOneWidget);
    await t.tap(find.text('Descuento'));
    await esperar(t);
    await t.tap(find.text('Porcentaje'));
    await esperar(t);
    await t.enterText(find.byType(TextField).last, '10');
    await esperar(t);
    // 10 % de $ 7.850 = $ 785
    expect(find.textContaining('785'), findsWidgets);
    await t.tap(find.text('Listo'));
    await esperar(t);
    expect(find.text('Descuento aplicado'), findsOneWidget);
    expect(find.textContaining('(10 %)'), findsOneWidget);
    expect(find.textContaining('7.065'), findsOneWidget); // total de la barra
  });

  testWidgets('descuento en pesos nunca pasa del total de la venta', (t) async {
    await abrir(t);
    await t.tap(find.text('Descuento'));
    await esperar(t);
    await t.enterText(find.byType(TextField).last, '99999');
    await esperar(t);
    await t.tap(find.text('Listo'));
    await esperar(t);
    expect(find.textContaining('7.850'), findsWidgets); // el descuento tope es el subtotal: total $ 0
    expect(find.text('Descuento aplicado'), findsOneWidget);
  });

  testWidgets('un toque sobre la cantidad abre "Gramos" y escribe el valor exacto', (t) async {
    await abrir(t);
    await t.tap(find.text('250 g'));
    await esperar(t);
    expect(find.text('Gramos exactos'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, '320');
    await esperar(t);
    await t.tap(find.text('Listo'));
    await esperar(t);
    expect(carrito.whereType<LineaVentaPesable>().single.gramos, 320);
  });

  testWidgets('escribir 0 en la cantidad saca la línea', (t) async {
    await abrir(t);
    await t.tap(find.text('250 g'));
    await esperar(t);
    await t.enterText(find.byType(TextField).last, '0');
    await esperar(t);
    await t.tap(find.text('Listo'));
    await esperar(t);
    expect(carrito.map((l) => l.nombreProducto), ['Cerveza lata 473 ml']);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('con el teclado: el campo no pierde el foco, Enter agrega el primero y queda listo para el siguiente '
      '(El dueño, 2026-10-09: "tiene que escribir y seleccionar")', (t) async {
    await abrir(t);
    await t.runAsync(() => PuertoLocal(baseLocalCompanion()).crearProducto(
          nombre: 'Coca Cola 2,25 L', esPesable: false, precioCentavos: 290000, costoCentavos: 200000, stock: 10, usuarioId: 1,
        ));
    final campo = find.byType(TextField).first;
    await t.tap(campo);
    // Se abre el teclado: el título se achica y el campo tiene que seguir con el foco.
    t.view.viewInsets = const FakeViewPadding(bottom: 600);
    await esperar(t);
    final editable = t.widget<EditableText>(find.descendant(of: campo, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);

    await t.enterText(campo, 'coca');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await esperar(t);
    expect(find.text('Coca Cola 2,25 L'), findsOneWidget);
    expect(find.textContaining('Enter para agregar'), findsOneWidget);

    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await esperar(t);
    expect(carrito.map((l) => l.nombreProducto), contains('Coca Cola 2,25 L'));
    expect(t.widget<TextField>(campo).controller!.text, isEmpty);
    expect(editable.focusNode.hasFocus, isTrue, reason: 'el teclado queda abierto para el siguiente producto');
  });
}

