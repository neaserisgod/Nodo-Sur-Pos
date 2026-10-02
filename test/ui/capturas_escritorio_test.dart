// Capturas del escritorio para revisar el diseño a ojo: dibujan las
// pantallas con la base de test y guardan PNG en `capturas/escritorio/`
// (carpeta ignorada por git). No comprueban pixeles: solo que cada pantalla
// se dibuje sin excepciones, en claro y en oscuro.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/historial/pantalla_historial.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';

import '../helpers/base_para_tests.dart';

final _clave = GlobalKey();

/// flutter_test no carga las fuentes del pubspec: sin esto todo se dibuja con
/// Ahem (cajas) y los textos desbordan por culpa del test, no de la app.
Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

Future<(AppDatabase, int, int)> _base() async {
  final db = baseDeTest();
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
  final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 3000000);
  for (final p in [
    ('Cerveza lata 473 ml', 210000, 150000, 48),
    ('Gaseosa cola 2,25 L', 290000, 200000, 4),
    ('Yerba 1 kg', 460000, 310000, 20),
    ('Alfajor triple', 120000, 70000, 60),
  ]) {
    await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: p.$1,
            precioCentavos: Value(p.$2),
            costoCentavos: Value(p.$3),
            stock: Value(p.$4),
          ),
        );
  }
  return (db, usuarioId, sesionId);
}

Future<void> _capturar(WidgetTester tester, String nombre, Widget Function() pantalla, {bool oscuro = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
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
  await tester.pump(const Duration(milliseconds: 600));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/escritorio/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_cargarFigtree);

  for (final oscuro in [false, true]) {
    final sufijo = oscuro ? ' (oscuro)' : '';

    testWidgets('venta$sufijo', (tester) async {
      final (db, _, _) = await _base();
      addTearDown(db.close);
      await _capturar(tester, 'venta', () => PantallaVenta(db: db), oscuro: oscuro);
    });

    testWidgets('dashboard$sufijo', (tester) async {
      final (db, _, _) = await _base();
      addTearDown(db.close);
      await _capturar(tester, 'dashboard', () => PantallaDashboard(db: db), oscuro: oscuro);
    });

    testWidgets('proveedores$sufijo', (tester) async {
      final (db, usuarioId, sesionId) = await _base();
      addTearDown(db.close);
      await _capturar(
        tester,
        'proveedores',
        () => PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: sesionId),
        oscuro: oscuro,
      );
    });

    testWidgets('historial$sufijo', (tester) async {
      final (db, usuarioId, _) = await _base();
      addTearDown(db.close);
      await _capturar(tester, 'historial', () => PantallaHistorial(db: db, usuarioId: usuarioId), oscuro: oscuro);
    });

    testWidgets('separaciones$sufijo', (tester) async {
      final (db, usuarioId, sesionId) = await _base();
      addTearDown(db.close);
      await _capturar(
        tester,
        'separaciones',
        () => PantallaSeparaciones(db: db, usuarioId: usuarioId, sesionCajaId: sesionId),
        oscuro: oscuro,
      );
    });

    testWidgets('configuracion$sufijo', (tester) async {
      final (db, usuarioId, _) = await _base();
      addTearDown(db.close);
      await _capturar(
        tester,
        'configuracion',
        () => PantallaConfiguracion(db: db, usuarioId: usuarioId),
        oscuro: oscuro,
      );
    });
  }
}
