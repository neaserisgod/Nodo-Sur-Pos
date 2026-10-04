// Capturas de las pantallas del mock del celular (390×844 @2x) en
// `capturas/companion-mock/`, para ponerlas al lado de las del paquete del mock.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_buscador_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_inicio_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_notificaciones_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/controlador_falso_ns.dart';

final _clave = GlobalKey();

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

/// Dibuja [pantalla] dentro del mismo marco que el mock y guarda el PNG.
Future<void> capturarNs(
  WidgetTester tester,
  String nombre,
  Widget pantalla, {
  bool oscuro = false,
  ControladorFalsoNs? controlador,
  PestaniaNs? barra,
  Future<void> Function(WidgetTester)? antes,
}) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final c = controlador ?? ControladorFalsoNs();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AppNs(
          controlador: c,
          version: 0,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.ns.paper,
              extendBody: true,
              body: SafeArea(bottom: false, child: pantalla),
              bottomNavigationBar: barra == null ? null : BarraInferiorNs(activa: barra, onSeleccionar: (_) {}, hayActualizacion: true),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
  if (antes != null) await antes(tester);
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 2);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/companion-mock/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _cargarFigtree();
  });

  testWidgets('03-inicio', (t) async {
    await capturarNs(t, '03-inicio', const PantallaInicioNs(), barra: PestaniaNs.inicio);
  });
  testWidgets('03-inicio oscuro', (t) async {
    await capturarNs(t, '03-inicio', const PantallaInicioNs(), barra: PestaniaNs.inicio, oscuro: true);
  });
  testWidgets('45-notificaciones', (t) async {
    await capturarNs(t, '45-notificaciones', const PantallaNotificacionesNs());
  });
  testWidgets('42-buscador-inicio', (t) async {
    await capturarNs(t, '42-buscador-inicio', const PantallaBuscadorNs(origen: PestaniaNs.inicio));
  });
}
