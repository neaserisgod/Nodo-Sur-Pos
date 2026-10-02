// Ayuda para los tests de widgets que además guardan una captura PNG de la
// pantalla (`capturas/pruebas/`, carpeta ignorada por git). Las capturas sirven
// para revisar el diseño a ojo; no comparan píxeles.
//
// Este archivo no estaba en el repositorio (quedó ignorado por `.gitignore`
// cuando se creó) y por eso 3 tests de `test/ui/proveedores/` no cargaban.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';

bool _fuenteCargada = false;

/// flutter_test no carga las fuentes del pubspec: sin esto todo se dibuja con
/// Ahem (cajas) y los textos desbordan por culpa del test, no de la app.
Future<void> _cargarFigtree() async {
  if (_fuenteCargada) return;
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
  _fuenteCargada = true;
}

/// Dibuja [pantalla] en una ventana de escritorio de 1440×900 y devuelve la
/// llave del `RepaintBoundary` que usa [guardarCaptura].
Future<GlobalKey> montarPantallaParaCaptura(
  WidgetTester tester, {
  required Widget pantalla,
  required ThemeData tema,
  Size tamano = const Size(1440, 900),
}) async {
  await _cargarFigtree();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llave = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: llave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tema,
        navigatorObservers: [routeObserver],
        home: pantalla,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return llave;
}

/// Guarda el estado actual de la pantalla en `capturas/pruebas/<nombre>.png`.
Future<void> guardarCaptura(WidgetTester tester, GlobalKey llave, String nombre) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    final limite = llave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/pruebas/$nombre.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
