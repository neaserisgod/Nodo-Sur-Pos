// Navbar superior: las secciones van como pastillas y Configuración como engranaje al final (no como una pastilla más).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/navbar_superior.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

void main() {
  testWidgets('Configuración no es pastilla: es el engranaje, y tocarlo la elige', (tester) async {
    String? elegida;
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.claro,
      home: Scaffold(
        body: NavbarSuperior(
          claveActiva: 'venta',
          items: const [
            ItemNavbarSuperior(clave: 'dashboard', etiqueta: 'Inicio'),
            ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta'),
            ItemNavbarSuperior(clave: 'configuracion', etiqueta: 'Configuración'),
          ],
          onSeleccionar: (c) => elegida = c,
        ),
      ),
    ));
    expect(find.text('Venta'), findsOneWidget);
    expect(find.text('Configuración'), findsNothing);
    await tester.tap(find.byKey(const Key('nav_configuracion')));
    expect(elegida, 'configuracion');
  });

  testWidgets('sin el item de Configuración no aparece el engranaje', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.claro,
      home: Scaffold(
        body: NavbarSuperior(claveActiva: 'venta', items: const [ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta')], onSeleccionar: (_) {}),
      ),
    ));
    expect(find.byKey(const Key('nav_configuracion')), findsNothing);
  });
}
