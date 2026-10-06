// Capturas de la PC al tamaño y con los datos del mock v4 (1920×1040 = la ventana de 1920×1080 menos la barra de título), para
// compararlas a ojo con `docs/mock-pc` y no perder la fidelidad visual 1:1. Guarda PNG en `capturas/v4/` (carpeta ignorada por git).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';

import '../helpers/base_para_tests.dart';

final _clave = GlobalKey();

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

/// El catálogo del mock (nombre, categoría, precio en pesos, stock, pesable).
const _catalogo = [
  ('Cerveza lata 473 ml', 'Bebidas', 2100, 48, false),
  ('Pan lactal grande', 'Panificados', 2800, 14, false),
  ('Coca-Cola 2,25 L', 'Bebidas', 4100, 60, false),
  ('Jamón cocido', 'Fiambres', 14600, 9000, true),
  ('Marlboro box 20', 'Cigarrillos', 4900, 30, false),
  ('Alfajor triple', 'Golosinas', 1200, 80, false),
  ('Leche entera 1 L', 'Lácteos', 1650, 40, false),
  ('Yerba mate 1 kg', 'Almacén', 5200, 25, false),
  ('Queso barra', 'Fiambres', 9800, 7000, true),
  ('Fernet 750 ml', 'Bebidas', 11500, 9, false),
];

Future<(AppDatabase, int)> _base() async {
  final db = baseDeTest();
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
  await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 3000000);
  final categorias = <String, int>{};
  for (final p in _catalogo) {
    categorias[p.$2] ??= await crearCategoria(db, p.$2);
  }
  for (final p in _catalogo) {
    await crearProducto(
      db,
      nombre: p.$1,
      categoriaId: categorias[p.$2],
      esPesable: p.$5,
      precioCentavos: p.$5 ? null : p.$3 * 100,
      costoCentavos: p.$5 ? null : (p.$3 * 100 * 0.65).round(),
      precioPorKiloCentavos: p.$5 ? p.$3 * 100 : null,
      costoPorKiloCentavos: p.$5 ? (p.$3 * 100 * 0.65).round() : null,
      stock: p.$5 ? 0 : p.$4,
      stockGramos: p.$5 ? p.$4 : null,
      stockMinimo: p.$5 ? null : (p.$4 < 15 ? 15 : null),
      usuarioId: usuarioId,
    );
  }
  return (db, usuarioId);
}

Future<void> _capturar(WidgetTester tester, String nombre, Widget Function() pantalla, {bool oscuro = false, Future<void> Function()? antes}) async {
  tester.view.physicalSize = const Size(1920, 1040);
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
  await tester.pump(const Duration(milliseconds: 600));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/v4/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_cargarFigtree);

  for (final oscuro in [false, true]) {
    final sufijo = oscuro ? ' (oscuro)' : '';

    testWidgets('venta con carrito$sufijo', (tester) async {
      final (db, _) = await _base();
      addTearDown(db.close);
      await _capturar(
        tester,
        'venta',
        () => PantallaVenta(db: db),
        oscuro: oscuro,
        antes: () async {
          final c = Provider.of<VentaControlador>(tester.element(find.byType(Scaffold).first), listen: false);
          final productos = await tester.runAsync(() => db.select(db.productos).get()) ?? [];
          Producto de(String n) => productos.firstWhere((p) => p.nombre == n);
          c.agregarProducto(de('Cerveza lata 473 ml'));
          c.agregarProducto(de('Cerveza lata 473 ml'));
          c.campoTexto.text = '250 jamón';
          c.agregarProducto(de('Jamón cocido'));
          c.campoTexto.clear();
          for (var i = 0; i < 3; i++) {
            c.agregarProducto(de('Pan lactal grande'));
          }
          c.elegirMedio(ComposicionPago.efectivo);
        },
      );
    });

    testWidgets('inicio$sufijo', (tester) async {
      final (db, _) = await _base();
      addTearDown(db.close);
      await _capturar(tester, 'inicio', () => PantallaDashboard(db: db), oscuro: oscuro);
    });
  }
}
