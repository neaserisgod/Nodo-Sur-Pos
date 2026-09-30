// Pruebas de humo con una base NUEVA de verdad: sin categorías, proveedores,
// productos ni gastos fijos (como arranca un comercio que recién instala el
// producto, antes de elegir una plantilla por rubro). Las pantallas
// principales tienen que abrir vacías sin romperse: los demás tests de UI
// parten de un catálogo de ejemplo (`helpers/base_para_tests.dart`) y no lo
// cubren.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/cierre/pantalla_cierre.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';

void _tamanioDeEscritorio(WidgetTester tester) {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, Widget pantalla) async {
  _tamanioDeEscritorio(tester);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: pantalla),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = (await db.select(db.usuarios).getSingle()).id;
  });
  tearDown(() => db.close());

  test('una base nueva trae el usuario inicial neutro y lo indispensable, sin datos de ningún comercio', () async {
    expect((await db.select(db.usuarios).getSingle()).nombre, 'Administrador');
    expect(await db.select(db.categorias).get(), isEmpty);
    expect(await db.select(db.proveedores).get(), isEmpty);
    expect(await db.select(db.gastosFijos).get(), isEmpty);
    expect(await db.select(db.clientes).get(), isEmpty);
    // La estructura que la app necesita para andar sí está.
    expect(await db.select(db.cajas).get(), hasLength(2));
    expect(await db.select(db.mediosDePago).get(), hasLength(2));
    expect(await db.select(db.configuracionTabla).get(), hasLength(1));
    expect(await db.select(db.configuracionNegocioTabla).get(), hasLength(1));
    expect(await db.select(db.accesosDirectos).get(), hasLength(6));
    expect(await db.select(db.seccionesMenu).get(), isNotEmpty);
    final productos = await db.select(db.productos).get();
    expect(productos.map((p) => p.nombre), ['Varios']);
  });

  testWidgets('la pantalla de venta abre vacía con una sesión de caja', (tester) async {
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await _pump(tester, PantallaVenta(db: db));
    expect(tester.takeException(), isNull);
    expect(find.byType(PantallaVenta), findsOneWidget);
  });

  testWidgets('proveedores abre sin ningún proveedor ni categoría', (tester) async {
    await _pump(tester, PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null));
    expect(tester.takeException(), isNull);
    expect(find.byType(PantallaProveedores), findsOneWidget);
  });

  testWidgets('configuración abre con los valores de fábrica', (tester) async {
    await _pump(tester, PantallaConfiguracion(db: db, usuarioId: usuarioId));
    expect(tester.takeException(), isNull);
    expect(find.byType(PantallaConfiguracion), findsOneWidget);
  });

  testWidgets('el cierre de una sesión sin ventas abre sin romperse', (tester) async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await _pump(tester, PantallaCierre(db: db, sesionId: sesionId, usuarioId: usuarioId));
    expect(tester.takeException(), isNull);
    expect(find.byType(PantallaCierre), findsOneWidget);
  });
}
