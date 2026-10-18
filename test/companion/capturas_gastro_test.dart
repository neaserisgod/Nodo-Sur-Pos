// Capturas de Nodo Gastro con el diseño del mock v5 (docs/mock-gastro/NodoGastro.html), en claro y oscuro (390×844 @2x), en
// `capturas/gastro/`: para ponerlas al lado del mock y ver que la app se parece.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/bienvenida/bienvenida_gastro.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_pedidos_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

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
  late AppDatabase db;

  setUpAll(_cargarFuentes);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
    // La base de prueba trae su usuario con la edición de almacén; recién después se pasa a Gastro.
    final usuario = (await db.select(db.usuarios).get()).first.id;
    edicionActual = Edicion.gastronomia;
    await guardarConfigPedidos(
        db, const ConfigPedidos(cadetePropio: true, zonas: [ZonaEnvio(nombre: 'Centro', costoCentavos: 150000)], minutosNormal: 30));
    await guardarConfigAgenda(db, ConfigAgenda(horario: HorarioAtencion({for (var d = 1; d <= 7; d++) d: (desdeMin: 660, hastaMin: 1410)})));
    Future<LineaPedido> linea(String nombre, int precio, int cantidad) async {
      final id = await crearProducto(db, nombre: nombre, precioCentavos: precio, usuarioId: usuario);
      final p = await (db.select(db.productos)..where((x) => x.id.equals(id))).getSingle();
      return LineaPedido(gid: p.globalId!, nombre: nombre, cantidad: cantidad, precioCentavos: precio);
    }

    final pollo = await linea('Pollo al spiedo', 1400000, 1);
    final papas = await linea('Papas fritas grandes', 600000, 1);
    final pizza = await linea('Pizza muzzarella', 1200000, 2);
    final mila = await linea('Milanesa napolitana con fritas', 1150000, 2);
    Future<int> pedido(CanalPedido canal, String nombre, List<LineaPedido> l, int minutosAntes, {String? nota, bool envio = false}) =>
        crearPedido(db,
            canal: canal,
            nombreCliente: nombre,
            lineas: l,
            usuarioId: usuario,
            nota: nota,
            formaEntrega: envio ? FormaEntrega.cadetePropio : FormaEntrega.retiro,
            direccion: envio ? 'Mitre 340, 2° B' : null,
            zona: envio ? const ZonaEnvio(nombre: 'Centro', costoCentavos: 150000) : null,
            ahora: _ahora.subtract(Duration(minutes: minutosAntes)));
    await pedido(CanalPedido.whatsapp, 'Juan Pérez', [pollo, papas], 0, nota: 'Sin sal las papas', envio: true);
    await pedido(CanalPedido.whatsapp, 'Rocío', [pizza], 3);
    for (final (nombre, l, antes) in [('Ezequiel R.', [pizza], 36), ('Lucía', [mila], 12), ('Diego', [pollo], 20)]) {
      await pedido(CanalPedido.mostrador, nombre, l, antes); // lo que carga el local entra directo a la cocina
    }
  });
  tearDown(() {
    edicionActual = Edicion.almacen;
    return db.close();
  });

  Future<void> capturar(WidgetTester tester, String nombre, {bool oscuro = false, Widget? pantalla}) async {
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
        home: pantalla ?? Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.ns.paper,
            extendBody: true,
            body: SafeArea(bottom: false, child: PantallaPedidosNs(db: db, usuarioId: 1, ahora: _ahora)),
            bottomNavigationBar: BarraInferiorNs(activa: PestaniaNs.inicio, onSeleccionar: (_) {}, conPedidos: true, pedidosNuevos: 2),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await limite.toImage(pixelRatio: 2);
      final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('capturas/gastro/$nombre${oscuro ? '-oscuro' : ''}.png');
      await archivo.create(recursive: true);
      await archivo.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('Pedidos', (tester) async {
    await capturar(tester, 'pedidos');
    await capturar(tester, 'pedidos', oscuro: true);
  });

  testWidgets('Bienvenida', (tester) async {
    for (var paso = 0; paso < 3; paso++) {
      await capturar(tester, 'bienvenida-${paso + 1}', pantalla: BienvenidaGastro(key: ValueKey(paso), alTerminar: (_) {}, pasoInicial: paso));
    }
  });
}
