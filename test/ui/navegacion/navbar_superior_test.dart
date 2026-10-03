// Navbar superior: las secciones van como pastillas y Configuración como engranaje al final (no como una pastilla más).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
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

  double anchoBusqueda(WidgetTester t) => t.getSize(find.byKey(const Key('nav_busqueda_abierta'))).width;

  Future<void> configuracion(WidgetTester t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final db = baseDeTest();
    addTearDown(db.close);
    await t.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, home: PantallaConfiguracion(db: db, usuarioId: 1)));
    await t.pumpAndSettle();
  }

  testWidgets('la lupa abre la búsqueda expandiéndose sobre la barra y la X la cierra', (t) async {
    await configuracion(t);
    final cerrada = anchoBusqueda(t);
    await t.tap(find.byKey(const Key('nav_buscar')));
    await t.pumpAndSettle();
    expect(anchoBusqueda(t), greaterThan(cerrada * 5));
    expect(find.text('Inicio'), findsOneWidget, reason: 'las pastillas siguen en el árbol, solo se desvanecen');
    await t.tap(find.byKey(const Key('nav_cerrar_busqueda')));
    await t.pumpAndSettle();
    expect(anchoBusqueda(t), cerrada);
  });

  testWidgets('Ctrl+F abre la búsqueda con el foco en el campo y Esc vacío la cierra', (t) async {
    await configuracion(t);
    final cerrada = anchoBusqueda(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyF);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(anchoBusqueda(t), greaterThan(cerrada));
    final campo = t.widget<TextField>(find.byKey(const Key('busqueda_contextual')));
    expect(campo.focusNode!.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(anchoBusqueda(t), cerrada);
  });

  testWidgets('la tecla Inicio lleva a Venta, pero no mientras se escribe en un campo', (t) async {
    await configuracion(t);
    await t.tap(find.byKey(const Key('nav_buscar')));
    await t.pumpAndSettle();
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
