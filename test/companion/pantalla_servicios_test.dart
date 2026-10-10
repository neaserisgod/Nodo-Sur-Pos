import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_servicios_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Servicios en el celular (`docs/PLAN-SERVICIOS.md`, etapa 2): servicios e insumos sobre la base del celular.
void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
  });
  tearDown(() async {
    modulosActuales.value = ModulosNegocio.todosActivos;
    await db.close();
  });

  Future<int> topCoat() => crearInsumo(
        db,
        nombre: 'Top coat',
        unidad: UnidadInsumo.ml,
        contenidoEnvaseMilesimas: 15000,
        costoEnvaseCentavos: 1100000,
        stockMilesimas: 2000,
        usuarioId: usuario,
      );

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester, {bool soloCelular = true}) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Scaffold(body: PantallaServiciosNs(db: db, usuarioId: usuario, soloCelular: soloCelular)),
    ));
    await esperar(tester);
  }

  testWidgets('con una PC avisa que los servicios todavía son solo del celular', (tester) async {
    await abrir(tester, soloCelular: false);
    expect(find.textContaining('modo "Solo celular"'), findsOneWidget);
    expect(find.text('+ Nuevo'), findsNothing);
  });

  testWidgets('sin servicios lo explica, y sin el módulo de insumos no hay segmento de Insumos', (tester) async {
    await abrir(tester);
    expect(find.textContaining('Todavía no cargaste ningún servicio'), findsOneWidget);
    expect(find.text('Insumos'), findsOneWidget);

    modulosActuales.value = ModulosNegocio({Modulo.insumos}, forma: FormaDeTrabajo.servicios);
    await tester.pumpAndSettle();
    expect(find.text('Insumos'), findsNothing);
  });

  testWidgets('da de alta un insumo y aparece en la lista con su costo por unidad', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('Insumos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Insumo'));
    await esperar(tester);

    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'Top coat');
    await tester.enterText(campos.at(1), '15');
    await tester.enterText(campos.at(2), '11000');
    await tester.enterText(campos.at(3), '2');
    await tester.enterText(campos.at(4), '3');
    await tester.tap(find.text('Guardar insumo'));
    await esperar(tester);

    final i = (await listarInsumos(db)).single;
    expect(i.insumo.nombre, 'Top coat');
    expect(i.insumo.contenidoEnvaseMilesimas, 15000);
    expect(i.insumo.costoCentavos, 1100000);
    expect(i.stockMilesimas, 2000);
    expect(i.stockBajo, isTrue);
    expect(find.text('Top coat'), findsOneWidget);
    expect(find.text('2 ml · \$ 734/ml'), findsOneWidget);
    expect(find.text('Poco stock'), findsOneWidget);
  });

  testWidgets('cargar una compra desde el insumo suma los envases al stock', (tester) async {
    await topCoat();
    await abrir(tester);
    await tester.tap(find.text('Insumos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top coat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cargar compra').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pumpAndSettle();
    expect(find.textContaining('Entran 30 ml'), findsOneWidget);
    await tester.tap(find.text('Sumar al stock'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6)); // el aviso se va solo

    expect((await listarInsumos(db)).single.stockMilesimas, 32000);
    expect(find.text('32 ml · \$ 734/ml'), findsOneWidget);
  });

  testWidgets('el creador calcula costo, alcanza para y el precio sugerido, y guarda el servicio con su receta', (tester) async {
    await topCoat();
    await abrir(tester);
    await tester.tap(find.text('+ Nuevo'));
    await esperar(tester);

    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'Kapping');
    await tester.enterText(campos.at(1), '60');
    await tester.tap(find.text('+ Agregar un insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top coat').last);
    await tester.pumpAndSettle();
    // Arranca en 0,1 ml; tres toques más llegan a 0,4.
    for (var k = 0; k < 3; k++) {
      await tester.tap(find.bySemanticsLabel('Más').first);
      await tester.pumpAndSettle();
    }
    expect(find.text('0,4 ml'), findsOneWidget);
    // 11.000 × 0,4 / 15 = 293,33 → $ 294. Alcanza para 5 (2 ml de 0,4).
    expect(find.text('\$ 294'), findsWidgets);
    expect(find.textContaining('alcanza para 5 servicios'), findsOneWidget);
    // 60 % sobre el precio: 294 / 0,4 = 735 → $ 800 a la centena.
    await tester.ensureVisible(find.text('Usar'));
    await tester.tap(find.text('Usar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar servicio'));
    await tester.tap(find.text('Guardar servicio'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));

    final s = (await listarServicios(db)).single;
    expect(s.servicio.nombre, 'Kapping');
    expect(s.servicio.duracionMinutos, 60);
    expect(s.servicio.precioCentavos, 80000);
    expect(s.receta.single.cantidadMilesimas, 400);
    expect(find.text('Kapping'), findsOneWidget);
    expect(find.text('1 h · cuesta \$ 294 · alcanza para 5'), findsOneWidget);
    expect(find.byType(EtiquetaStockNs), findsNothing);
  });
}
