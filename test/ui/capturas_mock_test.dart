// Capturas de la PC con los datos del mock v4, a 1920×1040 (el área útil del mock: 1920×1080 menos la barra de la
// ventana), para compararlas a ojo contra `capturas-mock/k_*.png`. Guardan PNG en `capturas/mock/` (ignorada por git).
// No comprueban píxeles: solo que cada pantalla se dibuje sin errores, en claro y en oscuro, y a 1366×768.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';

import '../helpers/datos_mock.dart';

final _clave = GlobalKey();

/// flutter_test no carga las fuentes del pubspec: sin esto todo se dibuja con cajas.
Future<void> _cargarFuentes() async {
  final fija = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fija.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await fija.load();
  final variable = FontLoader('FigtreeV')..addFont(rootBundle.load('fonts/FigtreeVariable.ttf'));
  await variable.load();
}

Future<void> capturarMock(
  WidgetTester tester,
  String nombre,
  Widget Function() pantalla, {
  bool oscuro = false,
  Size tamanio = const Size(1920, 1040),
  Future<void> Function()? antes,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaPlazoleta.claro,
        darkTheme: TemaPlazoleta.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        navigatorObservers: [routeObserver],
        home: pantalla(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  if (antes != null) {
    await antes();
    await tester.pump(const Duration(milliseconds: 600));
  }
  // Lo que lee la base de verdad (drift) no avanza con el reloj falso: se le da tiempo real y se vuelve a dibujar.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final sufijo = '${oscuro ? '-oscuro' : ''}${tamanio.width < 1900 ? '-${tamanio.width.toInt()}' : ''}';
    final archivo = File('capturas/mock/$nombre$sufijo.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_cargarFuentes);

  for (final oscuro in [false, true]) {
    for (final tamanio in [const Size(1920, 1040), const Size(1366, 728)]) {
      final sufijo = '${oscuro ? ' (oscuro)' : ''} ${tamanio.width.toInt()}';

      testWidgets('venta con carrito$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(
          tester,
          'venta',
          () => PantallaVenta(db: b.db),
          oscuro: oscuro,
          tamanio: tamanio,
          antes: () async {
            final c = Provider.of<VentaControlador>(tester.element(find.byType(Scaffold).first), listen: false);
            c.agregarProducto(b.productos['cerveza']!);
            c.agregarProducto(b.productos['cerveza']!);
            c.campoTexto.text = '250 jamon';
            c.agregarProducto(b.productos['jamon']!);
            c.agregarProducto(b.productos['pan']!);
            c.agregarProducto(b.productos['pan']!);
            c.agregarProducto(b.productos['pan']!);
            c.campoTexto.clear();
            c.elegirMedio(ComposicionPago.efectivo);
          },
        );
      });

      testWidgets('mega-menú de Historial$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-mega', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.text('Historial')));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 600));
        });
      });

      testWidgets('menú de caja$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-caja', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          await tester.tap(find.byKey(const Key('boton_caja')));
        });
      });

      testWidgets('inicio$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'inicio', () => PantallaDashboard(db: b.db), oscuro: oscuro, tamanio: tamanio);
      });

      testWidgets('inicio este mes$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'inicio-mes', () => PantallaDashboard(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          await tester.tap(find.text('Este mes'));
        });
      });

      testWidgets('venta vacía$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-vacia', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio);
      });
    }
  }
}
