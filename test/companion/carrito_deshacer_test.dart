import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  testWidgets('quitar una línea del carrito se puede deshacer', (tester) async {
    // Sin la fuente real todo se dibuja con Ahem y desborda por culpa del test.
    final cargador = FontLoader('Figtree');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
    }
    await cargador.load();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final carrito = <LineaVenta>[
      const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
      const LineaVentaPorUnidad(productoId: 'b', nombreProducto: 'Gaseosa cola', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 290000),
    ];
    final db = await tester.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    final servicio = PuertoLocal(baseLocalCompanion());
    await tester.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 2000000));
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Quitar').first);
    await tester.pump();
    expect(carrito.map((l) => l.nombreProducto), ['Gaseosa cola']);
    expect(find.text('Quitaste Cerveza lata'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Deshacer'));
    await tester.pump();
    expect(carrito.map((l) => l.nombreProducto), ['Cerveza lata', 'Gaseosa cola']);
  });
}
