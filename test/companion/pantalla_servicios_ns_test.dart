import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/barra_inferior_ns.dart';
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

/// Servicios en el celular (`docs/PLAN-SERVICIOS.md`, etapa 2): la lista con costo y "alcanza para", los insumos y el
/// creador con el calculador, sobre la base del celular.
void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
  });
  // La pantalla escucha los módulos hasta que el árbol se desarma, después del tearDown: se vuelven a "todo activo" al
  // final, no en cada test (con la base ya cerrada, la pantalla todavía montada recargaría).
  tearDown(() => db.close());
  tearDownAll(() => modulosActuales.value = ModulosNegocio.todosActivos);

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: Scaffold(body: PantallaServiciosNs(db: db, usuarioId: usuario))));
    await esperar(tester);
  }

  Future<int> topCoat({int stock = 15000}) async {
    final id = await crearInsumo(db, nombre: 'Top coat', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 15000, costoEnvaseCentavos: 1100000, usuarioId: usuario);
    await contarInsumo(db, insumoId: id, stockMilesimas: stock, usuarioId: usuario);
    return id;
  }

  testWidgets('sin servicios lo explica; con uno muestra duración, costo, para cuántos alcanza y la ganancia', (tester) async {
    await abrir(tester);
    expect(find.textContaining('Todavía no cargaste ningún servicio'), findsOneWidget);

    final tc = await tester.runAsync(topCoat);
    await tester.runAsync(() => crearServicio(db, nombre: 'Semipermanente manos', precioCentavos: 1800000, duracionMinutos: 60,
        receta: [(insumoId: tc!, milesimas: 400)], usuarioId: usuario));
    // Cualquier aviso de módulos recarga la lista (uno nuevo, no el mismo objeto).
    modulosActuales.value = ModulosNegocio(const {}, forma: FormaDeTrabajo.servicios);
    await esperar(tester);

    expect(find.text('Semipermanente manos'), findsOneWidget);
    // 11.000 × 0,4 / 15 = $294; alcanza para 15 / 0,4 = 37.
    expect(find.textContaining('1 h · cuesta \$ 294 · alcanza para 37'), findsOneWidget);
    expect(find.text('gana 98 %'), findsOneWidget);
  });

  testWidgets('la solapa Insumos lista lo que hay y avisa el poco stock; sin el módulo, no aparece', (tester) async {
    await tester.runAsync(() async {
      final id = await crearInsumo(db, nombre: 'Guantes', unidad: UnidadInsumo.u, contenidoEnvaseMilesimas: 100000, costoEnvaseCentavos: 900000,
          stockMinimoMilesimas: 20000, usuarioId: usuario);
      await contarInsumo(db, insumoId: id, stockMilesimas: 12000, usuarioId: usuario);
    });
    await abrir(tester);
    await tester.tap(find.text('Insumos'));
    await tester.pumpAndSettle();
    expect(find.text('Guantes'), findsOneWidget);
    expect(find.text('Poco stock'), findsOneWidget);
    expect(find.textContaining('12 u'), findsOneWidget);

    modulosActuales.value = ModulosNegocio(const {Modulo.insumos}, forma: FormaDeTrabajo.servicios);
    await esperar(tester);
    expect(find.text('Insumos'), findsNothing);
  });

  testWidgets('el creador calcula el costo en vivo, sugiere el precio y lo guarda con su receta', (tester) async {
    await tester.runAsync(topCoat);
    await abrir(tester);
    await tester.tap(find.text('+ Nuevo'));
    await esperar(tester);

    await tester.enterText(find.byType(TextField).first, 'Kapping');
    await tester.tap(find.text('+ Agregar un insumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top coat'));
    await tester.pumpAndSettle();
    // Arranca en 0,1 ml: 11.000 × 0,1 / 15 = $73,33 → $74.
    expect(find.text('\$ 74'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Más'));
    await tester.pumpAndSettle();
    expect(find.text('0,2 ml'), findsOneWidget);

    // El editor es una lista: con "Pide seña" (§21) el sugerido queda más abajo y hay que bajar hasta él.
    await tester.dragUntilVisible(find.text('Usar'), find.byType(ListView).last, const Offset(0, -200));
    await tester.tap(find.text('Usar'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar servicio'));
    await tester.tap(find.text('Guardar servicio'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6)); // el aviso se va solo

    final s = (await tester.runAsync(() => listarServicios(db, conManoDeObra: false)))!.single;
    expect(s.producto.nombre, 'Kapping');
    expect(s.receta.single.insumo.producto.nombre, 'Top coat');
    expect(s.producto.precioCentavos, s.precioSugeridoCentavos, reason: '"Usar" pone el sugerido');
  });

  test('la barra dice Servicios en un negocio de servicios', () {
    expect(const BarraInferiorNs(activa: PestaniaNs.inicio, onSeleccionar: _nada, conServicios: true).conServicios, isTrue);
  });
}

void _nada(PestaniaNs _) {}
