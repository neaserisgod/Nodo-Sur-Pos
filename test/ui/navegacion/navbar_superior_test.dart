// Navbar superior: las secciones van como pastillas y Configuración como engranaje al final (no como una pastilla más).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:la_plazoleta/ui/comparar_precios/pantalla_comparar_precios.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';
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

  double opacidadBusqueda(WidgetTester t) => t.widget<AnimatedOpacity>(find.byKey(const Key('nav_busqueda_abierta'))).opacity;

  Future<void> ctrlF(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  // Una pantalla con búsqueda propia en la barra (Comparar precios). Las rehechas del mock v4 (Configuración,
  // Proveedores...) llevan su buscador en la cabecera; ahí Ctrl+F abre el Asistente.
  Future<void> conBusquedaEnLaBarra(WidgetTester t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final db = baseDeTest();
    addTearDown(db.close);
    await t.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, home: PantallaCompararPrecios(db: db, usuarioId: 1)));
    await t.pumpAndSettle();
  }

  testWidgets('sin lupa a la vista (mock v4): Ctrl+F abre la búsqueda adentro de la barra y la X la cierra', (t) async {
    await conBusquedaEnLaBarra(t);
    expect(find.byKey(const Key('nav_buscar')), findsNothing);
    expect(opacidadBusqueda(t), 0);
    await ctrlF(t);
    expect(opacidadBusqueda(t), 1);
    expect(find.text('Inicio'), findsOneWidget, reason: 'las secciones siguen en el árbol, solo se desvanecen');
    await t.tap(find.byKey(const Key('nav_cerrar_busqueda')));
    await t.pumpAndSettle();
    expect(opacidadBusqueda(t), 0);
  });

  testWidgets('Ctrl+F abre la búsqueda con el foco en el campo y Esc vacío la cierra', (t) async {
    await conBusquedaEnLaBarra(t);
    await ctrlF(t);
    final campo = t.widget<TextField>(find.byKey(const Key('busqueda_contextual')));
    expect(campo.focusNode!.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(opacidadBusqueda(t), 0);
  });

  testWidgets('la tecla Inicio lleva a Venta, pero no mientras se escribe en un campo', (t) async {
    await conBusquedaEnLaBarra(t);
    await ctrlF(t);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pumpAndSettle();
    expect(find.byType(PantallaVenta), findsNothing, reason: 'con el foco en la búsqueda, Inicio mueve el cursor');
    await t.tap(find.byKey(const Key('nav_cerrar_busqueda')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pumpAndSettle();
    expect(find.byType(PantallaVenta), findsOneWidget);
  });
}

