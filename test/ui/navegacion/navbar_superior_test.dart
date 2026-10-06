// Navbar superior: las secciones van como pastillas y Configuración como engranaje al final (no como una pastilla más).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:la_plazoleta/ui/comparar_precios/pantalla_comparar_precios.dart';
import 'package:la_plazoleta/ui/encargues/pantalla_encargues.dart';
import 'package:la_plazoleta/ui/navegacion/navegacion_gestion.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/navbar_superior.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

void main() {
  _barraQuietaAlCambiarDeApartado();
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


void _barraQuietaAlCambiarDeApartado() {
  testWidgets('al cambiar de apartado la barra queda quieta: no se desvanece ni se mueve con la pantalla', (t) async {
    // La transición de la PC (fundido cruzado) está configurada para Windows; los tests corren como Android.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final db = baseDeTest();
    addTearDown(db.close);
    await t.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, home: PantallaSeparaciones(db: db, usuarioId: 1, sesionCajaId: null)));
    await t.pumpAndSettle();
    // Se mide la pastilla "Inicio": su texto no aparece en ninguna de las dos pantallas ("Encargues" es también título).
    final antes = t.getTopLeft(find.text('Inicio'));

    unawaited(navegarASeccionDeGestion(t.element(find.byType(PantallaSeparaciones)), 'encargues', db: db, usuarioId: 1));
    // `navegarASeccionDeGestion` lee la base antes de empujar: se espera a que la pantalla nueva exista (todavía
    // invisible) y recién ahí se congela la transición a la mitad.
    for (var i = 0; i < 50 && find.byType(PantallaEncargues, skipOffstage: false).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.byType(PantallaEncargues, skipOffstage: false), findsOneWidget, reason: 'la navegación empezó');
    await t.pump(const Duration(milliseconds: 60));
    // En plena transición hay UNA sola barra: la que vuela con el `Hero`, arriba de las dos pantallas (sin el `Hero`
    // habría dos, cada una dentro del fundido y el zoom de su pantalla). Está donde estaba y nada la desvanece.
    // (La barra de destino también existe, escondida hasta que termina el vuelo: por eso solo lo que está en pantalla.)
    final barra = find.text('Inicio');
    expect(barra, findsOneWidget, reason: 'una sola barra durante el cambio');
    expect(t.getTopLeft(barra), antes, reason: 'la barra no se corre');
    for (final f in t.widgetList<FadeTransition>(find.ancestor(of: barra, matching: find.byType(FadeTransition)))) {
      expect(f.opacity.value, 1, reason: 'la barra no entra en el fundido de la pantalla');
    }
    for (final e in t.widgetList<ScaleTransition>(find.ancestor(of: barra, matching: find.byType(ScaleTransition)))) {
      expect(e.scale.value, 1, reason: 'ni en el zoom');
    }
    await t.pumpAndSettle();
    expect(find.byType(PantallaEncargues), findsOneWidget);
    debugDefaultTargetPlatformOverride = null; // antes de que termine el test: Flutter lo exige
  });
}
