// Vender un servicio en el celular (`docs/PLAN-SERVICIOS.md`, etapa 3; Regla 20): aparece en la búsqueda con para cuántos
// alcanza, con candado si le falta un insumo, se ajusta lo que se usó y al cobrar descuenta los insumos.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int top;
  late List<LineaVenta> carrito;

  Future<void> abrir(WidgetTester t, {int stockTop = 1000}) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);

    db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    await t.runAsync(() async {
      await configurarRubro(db, PlantillaRubro.unas);
      top = await crearInsumo(db, nombre: 'Top coat', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 15000, costoEnvaseCentavos: 1100000,
          stockMilesimas: stockTop, usuarioId: 1);
      await guardarServicio(db, nombre: 'Kapping', precioCentavos: 2000000, duracionMinutos: 60, receta: [(insumoId: top, milesimas: 400)], usuarioId: 1);
    });
    final servicio = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0));
    carrito = <LineaVenta>[];
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(controlador: ControladorFalsoNs(), version: 0, child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito))),
      ),
    );
    await esperar(t);
  }

  Future<void> buscar(WidgetTester t, String texto) async {
    await t.enterText(find.byType(TextField).first, texto);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await esperar(t);
  }

  testWidgets('el servicio aparece en la búsqueda con su duración y para cuántos alcanza, y se cobra descontando el insumo', (t) async {
    await abrir(t);
    expect(find.text('Kapping'), findsOneWidget, reason: 'en Más vendidos de un negocio de servicios');

    await buscar(t, 'kap');
    expect(find.textContaining('1 h · Alcanza para 2'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await esperar(t);
    expect(carrito, hasLength(1));

    await t.tap(find.text('Cobrar'));
    await esperar(t);
    await t.tap(find.text('\$ 20.000'));
    await esperar(t);
    await t.tap(find.textContaining('Confirmar cobro'));
    await esperar(t);
    await esperar(t);

    expect(carrito, isEmpty);
    final linea = (await t.runAsync(() => db.select(db.lineasDeVenta).getSingle()))!;
    expect(linea.nombreProductoFoto, 'Kapping');
    expect(linea.esServicio, isTrue);
    final insumo = (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(top))).getSingle()))!;
    expect(insumo.stockMilesimas, 600);
  });

  testWidgets('sin el insumo, el servicio se ve con candado y "falta …" y no entra al carrito', (t) async {
    await abrir(t, stockTop: 300);
    await buscar(t, 'kap');
    expect(find.textContaining('Falta top coat'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is IconoNsWidget && w.icono == IconoNs.candado), findsOneWidget);
    await t.tap(find.text('Kapping').last);
    await esperar(t);
    expect(carrito, isEmpty);
    expect(find.textContaining('no se puede cobrar hasta que cargues la compra'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('ajustar lo que se usó cambia esa línea; con el módulo apagado no se ofrece', (t) async {
    await abrir(t);
    await buscar(t, 'kap');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await esperar(t);

    await t.tap(find.text('Ajustar'));
    await esperar(t);
    expect(find.text('0,4 ml'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Más').last);
    await t.pump();
    expect(find.text('0,5 ml'), findsOneWidget);
    await t.tap(find.text('Listo'));
    await esperar(t);
    expect((carrito.single as LineaVentaPorUnidad).insumosAjustados, {top: 500});
    expect(find.text('Insumos ajustados'), findsOneWidget);

    modulosActuales.value = ModulosNegocio({Modulo.ajustarInsumos}, forma: FormaDeTrabajo.servicios);
    await t.runAsync(() => configurarModulo(db, Modulo.ajustarInsumos, activo: false));
    await t.tap(find.bySemanticsLabel('Más').first);
    await esperar(t);
    expect(find.text('Ajustar'), findsNothing);
  });
}
