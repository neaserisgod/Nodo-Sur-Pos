// El menú armado de verdad (sin controlador falso): las pestañas Productos, Vender y Notificaciones tienen que cargar
// con el servicio que el menú resuelve DESPUÉS de abrirse.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_menu_companion.dart';
import 'package:la_plazoleta/companion/pantalla_consultar_precio.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_buscador_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_notificaciones_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cargador = FontLoader('Figtree');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
    }
    await cargador.load();
  });

  testWidgets('con el menú real, Productos y Vender cargan y Notificaciones abre', (t) async {
    SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Ana'});
    final db = await t.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    await t.runAsync(() => PuertoLocal(baseLocalCompanion()).abrirSesion(usuarioId: 1, fondoInicialCentavos: 3000000));
    t.view.physicalSize = const Size(390 * 2, 844 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, builder: (context, nav) => PuenteAppNs(child: nav!), home: const PantallaMenuCompanion()));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(seconds: 1));

    // Notificaciones desde la campana de Inicio.
    final campana = find.byWidgetPredicate((w) => w is BotonCircularNs && w.icono == IconoNs.campana);
    expect(campana, findsOneWidget);
    await t.tap(campana);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Notificaciones'), findsWidgets, reason: 'Notificaciones no abrió');
    expect(find.byType(PantallaNotificacionesNs), findsOneWidget);
    Navigator.of(t.element(find.byType(PantallaNotificacionesNs))).pop();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));

    // Las otras pantallas que se abren con push: Buscador de funciones y Consultar precio.
    final destinos = <String, Type>{'Buscá una función': PantallaBuscadorNs, 'Consultar': PantallaConsultarPrecio};
    for (final e in destinos.entries) {
      await t.ensureVisible(find.textContaining(e.key).first);
      await t.tap(find.textContaining(e.key).first, warnIfMissed: false);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      final pantalla = find.byType(e.value);
      expect(pantalla, findsOneWidget, reason: 'no abrió "${e.key}"');
      Navigator.of(t.element(pantalla)).pop();
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    await t.tap(find.text('Productos').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(EsqueletoListaNs), findsNothing, reason: 'Productos se quedó cargando');

    await t.tap(find.text('Vender').last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('escaneá o tocá un producto'), findsOneWidget, reason: 'Vender quedó en blanco');

    // El menú escucha los módulos con una consulta en vivo de drift (Solo celular): al cerrarla, drift agenda su limpieza
    // para el próximo instante. Se desarma el menú y se deja correr ese instante.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
