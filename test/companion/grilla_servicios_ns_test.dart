import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantallas/grilla_servicios_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';

import '../helpers/base_para_tests.dart';

/// Cobrar en un negocio de servicios (§20, etapa 3): la grilla de servicios y la línea que arma cada uno.
void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
  });
  tearDown(() => db.close());
  tearDownAll(() => modulosActuales.value = ModulosNegocio.todosActivos);

  Future<void> esperar(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pumpAndSettle();
  }

  testWidgets('muestra los servicios con precio y duración, y tocarlo arma la línea con el costo de sus insumos', (t) async {
    late int tintura;
    await t.runAsync(() async {
      tintura = await crearInsumo(db, nombre: 'Tintura', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 60000, costoEnvaseCentavos: 600000, usuarioId: usuario);
      await contarInsumo(db, insumoId: tintura, stockMilesimas: 20000, usuarioId: usuario);
      await crearServicio(db, nombre: 'Color', precioCentavos: 3000000, duracionMinutos: 90, receta: [(insumoId: tintura, milesimas: 40000)], usuarioId: usuario);
      await crearServicio(db, nombre: 'Corte de dama', precioCentavos: 1800000, duracionMinutos: 45, usuarioId: usuario);
      await crearServicio(db, nombre: 'Sin precio todavía', precioCentavos: 0, duracionMinutos: 30, usuarioId: usuario);
    });
    ServicioListado? elegido;
    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: Scaffold(body: GrillaServiciosNs(db: db, onElegir: (s) => elegido = s))));
    await esperar(t);

    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Corte de dama'), findsOneWidget);
    expect(find.text('Sin precio todavía'), findsNothing, reason: 'sin precio no se puede cobrar');
    expect(find.text('90 min'), findsOneWidget);
    // Hay 20 ml y el color usa 40: avisa, pero se puede tocar igual.
    expect(find.text('Falta tintura'), findsOneWidget);

    await t.tap(find.text('Color'));
    final linea = lineaDeServicio(elegido!);
    expect(linea.precioUnitarioCentavos, 3000000);
    expect(linea.costoUnitarioCentavos, 400000, reason: '40 ml × \$100, sin mano de obra');
    expect(linea.cantidad, 1);
  });

  testWidgets('sin el módulo de insumos no avisa faltantes', (t) async {
    await t.runAsync(() async {
      final tintura = await crearInsumo(db, nombre: 'Tintura', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 60000, costoEnvaseCentavos: 600000, usuarioId: usuario);
      await crearServicio(db, nombre: 'Color', precioCentavos: 3000000, duracionMinutos: 90, receta: [(insumoId: tintura, milesimas: 40000)], usuarioId: usuario);
    });
    modulosActuales.value = ModulosNegocio(const {Modulo.insumos}, forma: FormaDeTrabajo.servicios);
    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: Scaffold(body: GrillaServiciosNs(db: db, onElegir: (_) {}))));
    await esperar(t);
    expect(find.textContaining('Falta'), findsNothing);
  });
}
