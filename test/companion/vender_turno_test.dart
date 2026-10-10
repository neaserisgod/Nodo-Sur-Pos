// Cobrar un turno con seña en Vender del celular (`REGLAS-NEGOCIO.md` §21): se cobra solo lo que falta y el turno queda cobrado.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('el turno con seña se ve en el carrito, se cobra solo lo que falta y queda cobrado', (t) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    final servicio = PuertoLocal(baseLocalCompanion());
    late int corte;
    late int turnoId;
    await t.runAsync(() async {
      await configurarRubro(db, PlantillaRubro.barberia);
      corte = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, receta: const [], usuarioId: 1);
      final sesion = await servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0);
      turnoId = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: DateTime.now(), senaCentavos: 300000, sesionCajaId: sesion, usuarioId: 1);
    });
    final carrito = <LineaVenta>[
      LineaVentaPorUnidad(productoId: '$corte', nombreProducto: 'Corte', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 1000000),
    ];
    final turno = ValueNotifier<int?>(turnoId);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(
        controlador: ControladorFalsoNs(),
        version: 0,
        child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito, turno: turno)),
      ),
    ));
    await esperar(t);
    expect(find.text('Turno de Ana · ya dejó \$ 3.000 de seña'), findsOneWidget);

    await t.tap(find.text('Cobrar'));
    await esperar(t);
    expect(find.text('Falta cobrar'), findsOneWidget);
    expect(find.text('\$ 7.000'), findsWidgets);
    expect(find.textContaining('seña −\$ 3.000'), findsOneWidget);
    await t.tap(find.textContaining('Confirmar cobro de \$ 7.000'));
    await esperar(t);
    await esperar(t);

    expect(carrito, isEmpty);
    expect(turno.value, isNull);
    final fila = (await t.runAsync(() => (db.select(db.turnos)..where((x) => x.id.equals(turnoId))).getSingle()))!;
    expect(fila.estado, 'cobrado');
    final pagos = (await t.runAsync(() => db.select(db.pagos).get()))!;
    expect(pagos.map((p) => p.montoCentavos).toList()..sort(), [300000, 700000]);
  });
}
