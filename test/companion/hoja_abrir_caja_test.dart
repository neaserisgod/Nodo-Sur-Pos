// Abrir caja desde el celular pide el saldo de Mercado Pago (El dueño, 2026-10-09: "al abrir caja no me da el monto de
// Mercado Pago"): viene precargado con lo último contado y lo que se confirma es lo que queda en la caja.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/hoja_abrir_caja_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' as repo_ventas;

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Finder campo(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));

  testWidgets('precarga el MP del cierre anterior y abre con el monto corregido', (t) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = (await t.runAsync(() async => baseDeTest()))!;
    usarBaseLocalDeTest(db);
    final servicio = PuertoLocal(baseLocalCompanion());
    await t.runAsync(() async {
      await servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 0);
      await servicio.confirmarCierre(usuarioId: 1, efectivoContadoCentavos: 0, mpContadoCentavos: 4500000, lataContadoCentavos: 0);
    });

    bool? abierta;
    await t.pumpWidget(
      MaterialApp(
        theme: TemaCompanion.claro,
        home: AppNs(
          controlador: ControladorFalsoNs(),
          version: 0,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => abierta = await mostrarHojaAbrirCaja(context, servicio: servicio, usuarioId: 1),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('abrir'));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 300));
    }

    final mp = campo('Mercado Pago (lo que hay en la cuenta)');
    expect(t.widget<TextField>(mp).controller!.text, '45000');
    expect(find.textContaining('Precargado con lo último contado'), findsOneWidget);

    await t.enterText(mp, '46000');
    await t.tap(find.text('Abrir caja y continuar'));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.pump(const Duration(seconds: 5));

    expect(abierta, isTrue);
    final sesion = await t.runAsync(() => repo_ventas.sesionAbierta(db));
    expect(sesion?.saldoMpInicialCentavos, 4600000);
  });
}
