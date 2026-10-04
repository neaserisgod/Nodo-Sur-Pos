// Capturas de las pantallas del mock del celular (390×844 @2x) en
// `capturas/companion-mock/`, para ponerlas al lado de las del paquete del mock.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_consultar_precio.dart';
import 'package:la_plazoleta/companion/pantalla_movimiento_caja.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_buscador_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_caja_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_cierre_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_inicio_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_notificaciones_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/base_para_tests.dart';
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

  // ───────── Vender ─────────
  List<LineaVenta> tresLineas() => [
        const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata 473 ml', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
        const LineaVentaPesable(productoId: 'b', nombreProducto: 'Jamón cocido', proveedorId: null, gramos: 250, precioPorKiloCentavos: 1460000),
        const LineaVentaPorUnidad(productoId: 'c', nombreProducto: 'Pan lactal grande', proveedorId: null, cantidad: 3, precioUnitarioCentavos: 280000),
      ];

  Future<PuertoLocal> servicioConCaja(WidgetTester t, {bool abrir = true}) async {
    final db = await t.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    final servicio = PuertoLocal(baseLocalCompanion());
    if (abrir) await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 3000000));
    return servicio;
  }

  testWidgets('05-vender-vacio', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '05-vender-vacio', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []), barra: PestaniaNs.vender);
  });
  testWidgets('15-vender-caja-cerrada', (t) async {
    final servicio = await servicioConCaja(t, abrir: false);
    await capturarNs(t, '15-vender-caja-cerrada', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []), controlador: ControladorFalsoNs(abierta: false), barra: PestaniaNs.vender);
  });
  testWidgets('07-vender-carrito', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '07-vender-carrito', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), barra: PestaniaNs.vender);
  });
  testWidgets('07-vender-carrito oscuro', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '07-vender-carrito', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), barra: PestaniaNs.vender, oscuro: true);
  });
  testWidgets('08-vender-carrito-descuento', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '08-vender-carrito-descuento',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.tap(find.text('Aplicar descuento 10 %'));
        await t.pump(const Duration(milliseconds: 700));
      },
    );
  });
  testWidgets('09-cobro-efectivo', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '09-cobro-efectivo',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await t.tap(find.text('Cobrar'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await t.pump(const Duration(milliseconds: 800));
        await t.tap(find.text('\$\u00A020.000'));
        await t.pump(const Duration(milliseconds: 800));
      },
    );
  });
  testWidgets('14-venta-cobrada', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '14-venta-cobrada',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await t.tap(find.text('Cobrar'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await t.pump(const Duration(milliseconds: 800));
        await t.tap(find.text('\$\u00A020.000'));
        await t.pump(const Duration(milliseconds: 800));
        await t.tap(find.textContaining('Confirmar cobro'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
        await t.pump(const Duration(milliseconds: 1500));
      },
    );
  });

  // ───────── Caja ─────────
  testWidgets('29-caja-resumen', (t) async {
    await capturarNs(t, '29-caja-resumen', const PantallaCajaNs(), barra: PestaniaNs.caja);
  });
  testWidgets('29-caja-resumen oscuro', (t) async {
    await capturarNs(t, '29-caja-resumen', const PantallaCajaNs(), barra: PestaniaNs.caja, oscuro: true);
  });
  testWidgets('30-caja-separar', (t) async {
    await servicioConCaja(t);
    final c = ControladorFalsoNs()..segmentoCaja.value = 1;
    await capturarNs(t, '30-caja-separar', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja);
  });
  testWidgets('31-caja-ventas', (t) async {
    await servicioConCaja(t);
    final c = ControladorFalsoNs()..segmentoCaja.value = 2;
    await capturarNs(t, '31-caja-ventas', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja);
  });
  testWidgets('18-gasto-ingreso', (t) async {
    await capturarNs(t, '18-gasto-ingreso', const PantallaMovimientoCaja(), barra: null);
  });
  testWidgets('17-consultar-precio', (t) async {
    await servicioConCaja(t);
    await capturarNs(t, '17-consultar-precio', const PantallaConsultarPrecio());
  });
  testWidgets('33-cerrar-caja-paso1', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '33-cerrar-caja-paso1', PantallaCierreNs(servicio: servicio, usuarioId: 1));
  });
}
