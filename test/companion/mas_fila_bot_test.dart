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
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';

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

  testWidgets('Nodo Sur Servicios: sin encargues, sin el bot de Termux ni el modo PC; proveedores solo con insumos', (t) async {
    edicionActual = Edicion.servicios;
    final antes = modulosActuales.value;
    modulosActuales.value = ModulosNegocio.todosActivos.paraEdicionServicios();
    addTearDown(() {
      edicionActual = Edicion.almacen;
      modulosActuales.value = antes;
    });
    estadoBotCelular.value = const EstadoBot(tieneBot: true);
    await abrir(t);
    expect(find.text('Encargues'), findsNothing);
    expect(find.text('Bot de WhatsApp'), findsNothing);
    expect(find.textContaining('Modo:'), findsNothing);
    expect(find.text('Proveedores'), findsOneWidget);

    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.insumos, activo: false).paraEdicionServicios();
    await t.pumpWidget(const SizedBox());
    await abrir(t);
    expect(find.text('Proveedores'), findsNothing);
  });
}
