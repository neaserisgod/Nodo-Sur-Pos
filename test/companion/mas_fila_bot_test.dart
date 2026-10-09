// Más › Negocio muestra "Bot de WhatsApp" solo si el negocio tiene el bot (`docs/PLAN-BOT.md`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/bot_celular.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_mas_ns.dart';
import 'package:la_plazoleta/companion/servicio_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';

import '../helpers/controlador_falso_ns.dart';
import '../helpers/sitio_bot_falso.dart';

class _ConServicio extends ControladorFalsoNs {
  @override
  ServicioCompanion? get servicio => _ServicioQueNoSeUsa();
}

class _ServicioQueNoSeUsa implements ServicioCompanion {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> abrir(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(
        controlador: _ConServicio(),
        version: 0,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.ns.paper, body: const PantallaMasNs())),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
  }

  tearDown(() => estadoBotCelular.value = null);

  testWidgets('sin el bot no aparece; cuando el sitio dice que lo tiene, aparece', (t) async {
    await abrir(t);
    expect(find.text('Bot de WhatsApp'), findsNothing);

    final sitio = SitioBotFalso()..estadoBot = const EstadoBot(tieneBot: true);
    await t.runAsync(() => refrescarEstadoBot(acceso: sitio, forzar: true));
    await t.pump();
    expect(find.text('Bot de WhatsApp'), findsOneWidget);

    sitio.estadoBot = EstadoBot.sinBot;
    await t.runAsync(() => refrescarEstadoBot(acceso: sitio, forzar: true));
    await t.pump();
    expect(find.text('Bot de WhatsApp'), findsNothing);
  });
}
