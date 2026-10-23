// Capturas de Nodo Gastro con ventana de compu (Windows, `docs/PLAN-GASTRONOMIA.md`, "Nodo Gastro en Windows"): el menú lateral
// con Pedidos, la Carta y Vender a 1440×900, como las arma `PantallaMenuCompanion`. Guardan PNG en `capturas/gastro-escritorio/`
// (ignorada por git). No comparan píxeles: fallan si una pantalla no se dibuja o desborda.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_pedidos_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_servicios_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/capturas.dart';
import '../helpers/controlador_falso_ns.dart';

final _clave = GlobalKey();
final _ahora = DateTime(2026, 10, 17, 21, 2);

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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late int usuario;

  setUpAll(_cargarFuentes);

  Future<void> sembrar(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      db = baseDeTest();
      usarBaseLocalDeTest(db);
      usuario = (await db.select(db.usuarios).get()).first.id;
      await guardarConfigPedidos(
          db, const ConfigPedidos(cadetePropio: true, zonas: [ZonaEnvio(nombre: 'Centro', costoCentavos: 150000)], minutosNormal: 30));
      await guardarConfigAgenda(db, ConfigAgenda(horario: HorarioAtencion({for (var d = 1; d <= 7; d++) d: (desdeMin: 660, hastaMin: 1410)})));
      Future<int> insumo(String nombre, UnidadInsumo u, int envase, int costo, int stock, [int? minimo]) => crearInsumo(db,
          nombre: nombre,
          unidad: u,
          contenidoEnvaseMilesimas: envase * 1000,
          costoEnvaseCentavos: costo,
          stockInicialMilesimas: stock * 1000,
          stockMinimoMilesimas: minimo == null ? null : minimo * 1000,
          usuarioId: usuario);
      final carne = await insumo('Carne picada', UnidadInsumo.g, 1000, 1500000, 6000);
      final pan = await insumo('Pan de papa', UnidadInsumo.u, 4, 535000, 24);
      final cheddar = await insumo('Cheddar en fetas', UnidadInsumo.u, 8, 325000, 40);
      final papa = await insumo('Papas bastón', UnidadInsumo.g, 700, 455000, 3500, 4000);
      await crearServicio(db, nombre: 'Smash simple', precioCentavos: 750000, duracionMinutos: 6, usuarioId: usuario,
          receta: [(insumoId: carne, milesimas: 80000), (insumoId: pan, milesimas: 1000), (insumoId: cheddar, milesimas: 1000)]);
      await crearServicio(db, nombre: 'Smash doble', precioCentavos: 1100000, duracionMinutos: 8, usuarioId: usuario,
          receta: [(insumoId: carne, milesimas: 160000), (insumoId: pan, milesimas: 1000), (insumoId: cheddar, milesimas: 2000)]);
      await crearServicio(db, nombre: 'Papas fritas', precioCentavos: 400000, duracionMinutos: 6, usuarioId: usuario,
          receta: [(insumoId: papa, milesimas: 150000)]);
      await crearProductoDeVenta(db, nombre: 'Coca-Cola lata', precioCentavos: 250000, costoCentavos: 162400, stockInicial: 10, usuarioId: usuario);
      Future<LineaPedido> linea(String nombre, int precio, int cantidad) async {
        final p = await (db.select(db.productos)..where((x) => x.nombre.equals(nombre))).getSingle();
        return LineaPedido(gid: p.globalId!, nombre: nombre, cantidad: cantidad, precioCentavos: precio);
      }

      final doble = await linea('Smash doble', 1100000, 2);
      final simple = await linea('Smash simple', 750000, 1);
      final papas = await linea('Papas fritas', 400000, 1);
      Future<int> pedido(CanalPedido canal, String nombre, List<LineaPedido> l, int minutosAntes, {String? nota, bool envio = false}) =>
          crearPedido(db,
              canal: canal,
              nombreCliente: nombre,
              lineas: l,
              usuarioId: usuario,
              nota: nota,
              formaEntrega: envio ? FormaEntrega.cadetePropio : FormaEntrega.retiro,
              direccion: envio ? 'Bustillo km 13,5' : null,
              zona: envio ? const ZonaEnvio(nombre: 'Centro', costoCentavos: 150000) : null,
              ahora: _ahora.subtract(Duration(minutes: minutosAntes)));
      await pedido(CanalPedido.whatsapp, 'Juan Pérez', [doble, papas], 0, nota: 'Una sin cebolla', envio: true);
      await pedido(CanalPedido.whatsapp, 'Rocío', [simple], 3);
      for (final (nombre, l, antes) in [('Ezequiel R.', [doble], 36), ('Lucía', [simple, papas], 12), ('Diego', [doble], 20)]) {
        await pedido(CanalPedido.mostrador, nombre, l, antes);
      }
    });
    edicionActual = Edicion.gastronomia;
    modulosActuales.value = const ModulosNegocio({Modulo.cajaAparte}, forma: FormaDeTrabajo.gastronomia);
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

  /// La disposición de la compu tal como la arma `PantallaMenuCompanion` con la ventana ancha.
  Future<void> abrir(WidgetTester tester, PestaniaNs activa, Widget pantalla, {bool oscuro = false}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AppNs(
          controlador: ControladorFalsoNs(modo: ModoUso.soloCelular),
          version: 0,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.ns.paper,
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MenuLateralNs(activa: activa, onSeleccionar: (_) {}),
                  Expanded(child: ConMenuLateralNs(child: pantalla)),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await esperar(tester);
  }

  Future<void> guardar(WidgetTester tester, String nombre, {bool oscuro = false}) => tester.runAsync(() async {
        final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await limite.toImage(pixelRatio: 1);
        final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
        final archivo = File('capturas/gastro-escritorio/$nombre${oscuro ? '-oscuro' : ''}.png');
        await archivo.create(recursive: true);
        await archivo.writeAsBytes(bytes!.buffer.asUint8List());
      });

  for (final oscuro in temasDeCaptura) {
    final s = oscuro ? ' (oscuro)' : '';
    testWidgets('pedidos$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PestaniaNs.inicio, PantallaPedidosNs(db: db, usuarioId: usuario, ahora: _ahora), oscuro: oscuro);
      expect(find.text('Juan Pérez'), findsWidgets);
      await guardar(tester, 'pedidos', oscuro: oscuro);
    });
    testWidgets('carta$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PestaniaNs.productos, AnchoLecturaNs(ancho: anchoCartaNs, child: PantallaServiciosNs(db: db, usuarioId: usuario)), oscuro: oscuro);
      expect(find.text('Smash doble'), findsWidgets);
      await guardar(tester, 'carta', oscuro: oscuro);
    });
    testWidgets('vender$s', (tester) async {
      await sembrar(tester);
      final servicio = PuertoLocal(baseLocalCompanion());
      await tester.runAsync(() => servicio.abrirSesion(usuarioId: usuario, fondoInicialCentavos: 0));
      final carrito = <LineaVenta>[];
      await abrir(tester, PestaniaNs.vender,
          PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: usuario, carrito: carrito), oscuro: oscuro);
      // La grilla de platos y el cobro al costado, como el Cobrar de servicios.
      expect(find.text('Tocá un plato, una bebida o un combo para sumarlo.'), findsOneWidget);
      await guardar(tester, 'vender', oscuro: oscuro);
      await tester.tap(find.text('Smash doble').first);
      await tester.tap(find.text('Papas fritas').first);
      await esperar(tester);
      expect(find.text('Tocá un plato, una bebida o un combo para sumarlo.'), findsNothing);
      await guardar(tester, 'vender-cobro', oscuro: oscuro);
    });
  }
}
