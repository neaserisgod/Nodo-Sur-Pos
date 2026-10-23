// Capturas de Nodo Gastro, el resto de las pestañas (Carta, Vender, Caja, cierre y Más) con el diseño del mock v5
// (docs/mock-gastro/NodoGastro.html), en `capturas/gastro/`. No comparan píxeles: fallan si una pantalla no se dibuja o desborda.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_caja_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_cierre_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_mas_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_servicios_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

final _clave = GlobalKey();

Future<void> _cargarFuentes() async {
  final bricolage = FontLoader('Bricolage');
  for (final w in [600, 700, 800]) {
    bricolage.addFont(rootBundle.load('fonts/BricolageGrotesque-$w.ttf'));
  }
  final geist = FontLoader('Geist');
  for (final w in [400, 500, 600, 700]) {
    geist.addFont(rootBundle.load('fonts/Geist-$w.ttf'));
  }
  await Future.wait([bricolage.load(), geist.load()]);
}

void main() {
  late AppDatabase db;
  late int usuario;
  late PuertoLocal servicio;

  setUpAll(_cargarFuentes);

  Future<void> sembrar(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      db = baseDeTest();
      usuario = (await db.select(db.usuarios).get()).first.id;
      usarBaseLocalDeTest(db);
      servicio = PuertoLocal(baseLocalCompanion());
      await servicio.abrirSesion(usuarioId: usuario, fondoInicialCentavos: 2000000);
      Future<int> insumo(String nombre, UnidadInsumo u, int envase, int costo, int stock, [int? minimo]) => crearInsumo(db,
          nombre: nombre,
          unidad: u,
          contenidoEnvaseMilesimas: envase * 1000,
          costoEnvaseCentavos: costo,
          stockInicialMilesimas: stock * 1000,
          stockMinimoMilesimas: minimo == null ? null : minimo * 1000,
          usuarioId: usuario);
      final pollo = await insumo('Pollo entero', UnidadInsumo.g, 1600, 560000, 42000);
      final papa = await insumo('Papa', UnidadInsumo.g, 1000, 150000, 18000);
      final muzza = await insumo('Muzzarella', UnidadInsumo.g, 1000, 940000, 2100, 3000);
      final acelga = await insumo('Acelga (atado)', UnidadInsumo.u, 1, 150000, 2, 4);
      final spiedo = await crearServicio(db, nombre: 'Pollo al spiedo', precioCentavos: 1400000, duracionMinutos: 15, receta: [(insumoId: pollo, milesimas: 1600000)], usuarioId: usuario);
      await crearServicio(db, nombre: 'Papas fritas grandes', precioCentavos: 600000, duracionMinutos: 10, receta: [(insumoId: papa, milesimas: 600000)], usuarioId: usuario);
      await crearServicio(db, nombre: 'Pizza muzzarella', precioCentavos: 1200000, duracionMinutos: 18, receta: [(insumoId: muzza, milesimas: 350000)], usuarioId: usuario);
      await crearServicio(db, nombre: 'Tarta de verdura', precioCentavos: 900000, duracionMinutos: 25, receta: [(insumoId: acelga, milesimas: 1000)], usuarioId: usuario);
      final coca = await crearProductoDeVenta(db, nombre: 'Coca-Cola 1,5 L', precioCentavos: 380000, costoCentavos: 240000, stockInicial: 24, usuarioId: usuario);
      await guardarPromo(db, nombre: 'Combo pollo', articulos: [(productoId: spiedo, cantidad: 1), (productoId: coca, cantidad: 1)], gananciaBp: 3000, usuarioId: usuario);
    });
    edicionActual = Edicion.gastronomia;
    modulosActuales.value = const ModulosNegocio({Modulo.cajaAparte}, forma: FormaDeTrabajo.gastronomia); // sin la lata de cigarrillos
    addTearDown(() {
      edicionActual = Edicion.almacen;
      modulosActuales.value = ModulosNegocio.todosActivos;
    });
    addTearDown(() => tester.runAsync(db.close));
  }

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> abrir(WidgetTester tester, Widget pantalla, {bool oscuro = false, PestaniaNs? barra, ControladorFalsoNs? controlador}) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AppNs(
          // Nodo Gastro no tiene PC: anda siempre como "solo celular".
          controlador: controlador ?? ControladorFalsoNs(modo: ModoUso.soloCelular),
          version: 0,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.ns.paper,
              extendBody: true,
              body: SafeArea(bottom: false, child: pantalla),
              bottomNavigationBar: barra == null ? null : BarraInferiorNs(activa: barra, onSeleccionar: (_) {}, conPedidos: true, pedidosNuevos: 2),
            ),
          ),
        ),
      ),
    ));
    await esperar(tester);
  }

  Future<void> guardar(WidgetTester tester, String nombre, {bool oscuro = false}) => tester.runAsync(() async {
        final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await limite.toImage(pixelRatio: 2);
        final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
        final archivo = File('capturas/gastro/$nombre${oscuro ? '-oscuro' : ''}.png');
        await archivo.create(recursive: true);
        await archivo.writeAsBytes(bytes!.buffer.asUint8List());
      });

  List<LineaVenta> carrito() => const [
        LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Pollo al spiedo', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 1400000),
        LineaVentaPorUnidad(productoId: 'b', nombreProducto: 'Papas fritas grandes', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 600000),
        LineaVentaPorUnidad(productoId: 'c', nombreProducto: 'Coca-Cola 1,5 L', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 380000),
      ];

  for (final oscuro in [false, true]) {
    final s = oscuro ? ' (oscuro)' : '';
    testWidgets('carta$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PantallaServiciosNs(db: db, usuarioId: usuario), oscuro: oscuro, barra: PestaniaNs.productos);
      await guardar(tester, 'carta', oscuro: oscuro);
      await tester.tap(find.text('Stock'));
      await esperar(tester);
      await guardar(tester, 'carta-stock', oscuro: oscuro);
    });
    testWidgets('editor de plato$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PantallaEditorServicioNs(db: db, usuarioId: usuario), oscuro: oscuro);
      await guardar(tester, 'carta-plato-nuevo', oscuro: oscuro);
    });
    testWidgets('vender vacío$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: usuario, carrito: const []), oscuro: oscuro, barra: PestaniaNs.vender);
      await guardar(tester, 'vender-vacio', oscuro: oscuro);
    });
    testWidgets('vender$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: usuario, carrito: carrito()), oscuro: oscuro, barra: PestaniaNs.vender);
      await guardar(tester, 'vender', oscuro: oscuro);
    });
    testWidgets('caja$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, const PantallaCajaNs(), oscuro: oscuro, barra: PestaniaNs.caja);
      await guardar(tester, 'caja', oscuro: oscuro);
    });
    testWidgets('cierre$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PantallaCierreNs(servicio: servicio, usuarioId: usuario), oscuro: oscuro);
      await guardar(tester, 'cierre', oscuro: oscuro);
    });
    testWidgets('más$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, const PantallaMasNs(), oscuro: oscuro, barra: PestaniaNs.mas);
      await guardar(tester, 'mas', oscuro: oscuro);
    });
  }
}
