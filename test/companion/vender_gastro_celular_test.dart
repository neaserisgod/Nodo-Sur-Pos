// Vender de Nodo Gastro en el celular (El dueño, 20/10/2026): la grilla de platos con el carrito vacío y, con algo en el
// carrito, "+ Plato" y "+ Bebida u otro". Antes caía en la vista del almacén y cada plato había que buscarlo por nombre.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    final bricolage = FontLoader('Bricolage');
    for (final w in [600, 700, 800]) {
      bricolage.addFont(rootBundle.load('fonts/BricolageGrotesque-$w.ttf'));
    }
    final geist = FontLoader('Geist');
    for (final w in [400, 500, 600, 700]) {
      geist.addFont(rootBundle.load('fonts/Geist-$w.ttf'));
    }
    await Future.wait([bricolage.load(), geist.load()]);
  });

  Future<void> esperar(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 700));
  }

  testWidgets('con el carrito vacío se ve toda la carta; tocar un plato lo suma y queda un solo "+ Agregar"', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    late AppDatabase db;
    late int usuario;
    await t.runAsync(() async {
      db = baseDeTest();
      usarBaseLocalDeTest(db);
      usuario = (await db.select(db.usuarios).get()).first.id;
      await crearServicio(db, nombre: 'Smash doble', precioCentavos: 1100000, duracionMinutos: 8, usuarioId: usuario);
      await crearServicio(db, nombre: 'Papas fritas', precioCentavos: 400000, duracionMinutos: 6, usuarioId: usuario);
    });
    addTearDown(() => t.runAsync(db.close));
    edicionActual = Edicion.gastronomia;
    modulosActuales.value = const ModulosNegocio({Modulo.cajaAparte}, forma: FormaDeTrabajo.gastronomia);
    addTearDown(() {
      edicionActual = Edicion.almacen;
      modulosActuales.value = ModulosNegocio.todosActivos;
    });

    final servicio = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() => servicio.abrirSesion(usuarioId: usuario, fondoInicialCentavos: 0));
    final carrito = <LineaVenta>[];
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(
        controlador: ControladorFalsoNs(),
        version: 0,
        child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: usuario, carrito: carrito)),
      ),
    ));
    await esperar(t);

    expect(find.text('Smash doble'), findsWidgets);
    expect(find.text('Más vendidos'), findsNothing);
    expect(find.text('+ Bebida u otro'), findsNothing);

    await t.tap(find.text('Smash doble').first);
    await esperar(t);
    expect(carrito, hasLength(1));
    expect(find.text('+ Agregar'), findsOneWidget);
    expect(find.text('+ Bebida u otro'), findsNothing);

    // "+ Agregar" abre la misma grilla en una hoja.
    await t.tap(find.text('+ Agregar'));
    await esperar(t);
    await t.tap(find.text('Papas fritas').last);
    await esperar(t);
    expect(carrito, hasLength(2));
  });
}
