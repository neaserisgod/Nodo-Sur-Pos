// La Agenda del celular (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4).
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_agenda_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final lunes = DateTime(2026, 10, 12);
  late AppDatabase db;
  late int corte;
  late ControladorFalsoNs app;

  Future<void> abrir(WidgetTester t, {bool soloCelular = true, Future<void> Function()? antes}) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(430 * 2, 1100 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
    modulosActuales.value = ModulosNegocio({Modulo.profesionales}, forma: FormaDeTrabajo.servicios);

    db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    await t.runAsync(() async {
      await configurarRubro(db, PlantillaRubro.barberia);
      await configurarModulo(db, Modulo.profesionales, activo: false);
      corte = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 60, receta: const [], usuarioId: 1);
      await abrirSesion(db, usuarioId: 1, fondoInicialCentavos: 0);
      await antes?.call();
    });
    app = ControladorFalsoNs();
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(controlador: app, version: 0, child: Scaffold(body: PantallaAgendaNs(db: db, usuarioId: 1, soloCelular: soloCelular, hoy: lunes))),
    ));
    await esperar(t);
  }

  testWidgets('con una PC avisa que la agenda todavía es solo del celular', (t) async {
    await abrir(t, soloCelular: false);
    expect(find.textContaining('modo "Solo celular"'), findsOneWidget);
  });

  testWidgets('un día vacío muestra el horario como libre; anotar un turno con seña lo pone en el día', (t) async {
    await abrir(t);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Libre hasta las 20:00'), findsOneWidget);

    await t.tap(find.text('+ Turno'));
    await esperar(t);
    expect(find.text('Nuevo turno'), findsOneWidget);
    final campos = find.descendant(of: find.byType(HojaNs), matching: find.byType(TextField));
    await t.enterText(campos.at(0), 'Lauti');
    await t.enterText(campos.at(2), '10');
    await t.enterText(campos.at(3), '3000');
    await t.pump();
    await t.tap(find.text('Anotar turno'));
    await esperar(t);
    await t.pump(const Duration(seconds: 6));

    final turnos = (await t.runAsync(() => turnosDelDia(db, lunes)))!;
    expect(turnos.single.cliente.nombre, 'Lauti');
    expect(turnos.single.turno.inicio, DateTime(2026, 10, 12, 10));
    expect(turnos.single.turno.senaCentavos, 300000);
    expect(find.text('Lauti'), findsOneWidget);
    expect(find.textContaining('Confirmado · Seña'), findsOneWidget);
    expect(find.text('Libre hasta las 10:00'), findsOneWidget);
    expect(find.text('Libre hasta las 20:00'), findsOneWidget, reason: 'de 11 a 20');
  });

  testWidgets('un turno que se pisa no se anota y dice con cuál choca', (t) async {
    await abrir(t, antes: () => anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: DateTime(2026, 10, 12, 10), usuarioId: 1));
    await t.tap(find.byWidgetPredicate((w) => w is BotonCircularNs && w.icono == IconoNs.masMas));
    await esperar(t);
    final campos = find.descendant(of: find.byType(HojaNs), matching: find.byType(TextField));
    await t.enterText(campos.at(0), 'Bea');
    await t.enterText(campos.at(2), '10:30');
    await t.tap(find.text('Anotar turno'));
    await esperar(t);
    expect(find.textContaining('Se pisa con el turno de Ana a las 10:00'), findsOneWidget);
  });

  testWidgets('llegó y cobrar: el turno pasa a "Llegó" y cobrar lo lleva a Vender con su servicio y el turno', (t) async {
    late int id;
    await abrir(t, antes: () async => id = await anotarTurno(db, cliente: 'Ana', servicioId: corte, inicio: DateTime(2026, 10, 12, 10), usuarioId: 1));
    await t.tap(find.text('Ana'));
    await esperar(t);
    await t.tap(find.text('Llegó'));
    await esperar(t);
    expect(find.textContaining('Llegó'), findsOneWidget);

    await t.tap(find.text('Ana'));
    await esperar(t);
    await t.tap(find.text('Cobrar este turno'));
    await esperar(t);
    expect(app.llamadas, contains('pestania:vender'));
    expect(app.turnoEnVenta.value, id);
    expect((app.carrito.single as LineaVentaPorUnidad).productoId, '$corte');
  });
}
