// Cerrar caja del mock (lote 2): primero se cuenta a ciegas, después se revisa y recién "Cerrar caja" cierra.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_cierre_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

Future<void> esperar(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Finder campo(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));

  late PuertoLocal servicio;

  Future<void> abrir(WidgetTester t) async {
    final cargador = FontLoader('Figtree');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
    }
    await cargador.load();
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = await t.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    servicio = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 3000000));
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(controlador: ControladorFalsoNs(), version: 0, child: PantallaCierreNs(servicio: servicio, usuarioId: 1)),
      ),
    );
    await esperar(t);
  }

  testWidgets('etapa 1 no muestra lo esperado; la etapa 2 sí, y sin las tres cuentas no cierra', (t) async {
    await abrir(t);
    expect(find.text('Etapa 1 de 2'.toUpperCase()), findsOneWidget);
    expect(find.text('Caja esperada'), findsNothing); // a ciegas
    // Sin contar nada no avanza.
    await t.tap(find.text('Confirmar conteo'));
    await esperar(t);
    expect(find.text('Contá el efectivo y anotalo antes de confirmar'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));

    await t.enterText(campo('Efectivo contado'), '30000');
    await esperar(t);
    await t.tap(find.text('Confirmar conteo'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await esperar(t);
    expect(find.text('Revisá antes de cerrar'), findsOneWidget);
    expect(find.text('Caja esperada'), findsOneWidget);
    expect(find.text('Cuadró'), findsOneWidget); // fondo 30.000 contado: coincide

    // Todavía falta MP y lata: "Cerrar caja" avisa y no cierra.
    await t.tap(find.text('Cerrar caja').last);
    await esperar(t);
    expect(find.text('Falta el efectivo contado, el MP contado o la lata contada'), findsOneWidget);
    expect(find.text('Caja cerrada'), findsNothing);
    await t.pump(const Duration(seconds: 4));
  });
}
