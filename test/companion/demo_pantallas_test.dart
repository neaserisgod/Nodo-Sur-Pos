// La demo (horsepos.com/demo/, `docs/PLAN-DEMO-SERVICIOS.md`): la franja de arriba y la elección del negocio se dibujan sin
// errores en el ancho de un celular, y elegir un negocio entra a la app con el dueño.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/demo/demo.dart';
import 'package:la_plazoleta/companion/demo/franja_demo.dart';
import 'package:la_plazoleta/companion/demo/pantalla_elegir_demo.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

void main() {
  tearDown(() => modoDemo = false);

  testWidgets('la franja y "¿Qué negocio querés ver?" entran en un celular angosto', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    modoDemo = true;
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      builder: (context, navegador) => ConFranjaDemo(child: navegador!),
      home: const PantallaElegirDemo(),
    ));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(FranjaDemo), findsOneWidget);
    expect(find.text('Probar gratis'), findsOneWidget);
    expect(find.text('¿Qué negocio querés ver?'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
