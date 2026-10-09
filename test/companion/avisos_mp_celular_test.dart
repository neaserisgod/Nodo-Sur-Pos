// Avisos de Mercado Pago en el celular (El dueño, 2026-10-09: independizar el celular): el mismo servicio de la PC sobre la base
// del celular. Se ven en Notificaciones y "Visto" los saca.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_notificaciones_ns.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/repositorio_avisos_mp.dart';
import 'package:la_plazoleta/domain/avisos_mp.dart';
import 'package:la_plazoleta/servicios/avisos_mp_servicio.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('un contracargo se ve en Notificaciones y "Visto" lo saca', (t) async {
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final db = (await t.runAsync(() async => baseDeTest()))!;
    final avisos = ServicioAvisosMp(db: db, almacen: AlmacenCuentaEnMemoria(), cliente: ClienteNube(http: MockClient((_) async => http.Response('[]', 200))));
    avisosMpCompanion = avisos;
    addTearDown(() => avisosMpCompanion = null);
    await t.runAsync(() async {
      await guardarAvisosMp(db, [
        AvisoMp(idServidor: 1, tipo: TipoAvisoMp.contracargo, mpId: 'cb1', creado: DateTime.now(), montoCentavos: 500000, estado: 'opened'),
      ]);
      await avisos.recalcular();
    });
    expect(avisos.pendientes.value, hasLength(1));

    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: AppNs(controlador: ControladorFalsoNs(), version: 0, child: const PantallaNotificacionesNs())));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('Visto'), findsOneWidget);
    expect(find.text(avisos.pendientes.value.single.titulo), findsOneWidget);

    await t.tap(find.text('Visto'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 300));
    expect(avisos.pendientes.value, isEmpty);
    expect(find.text('Visto'), findsNothing);
  });
}
