import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_config_pedidos_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/servicios/comandera_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Configurar los pedidos de una rotisería (`REGLAS-NEGOCIO.md` §22): entregas opcionales, zonas con costo y demora, cómo se
/// cobra, los tiempos de la cocina y si lo de WhatsApp entra solo.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
  });
  tearDown(() => db.close());

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester, {ComanderaPoint? comandera}) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PantallaConfigPedidosNs(db: db, comandera: comandera))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await esperar(tester);
  }

  Finder campo(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(TextField));

  testWidgets('prende el envío con cadete, carga una zona, el pago adelantado y que entren solos', (tester) async {
    await abrir(tester);
    expect(find.text('Zonas de envío'), findsNothing);

    await tester.tap(find.byKey(const Key('pedidos_cadete')));
    await tester.pumpAndSettle();
    expect(find.text('ZONAS DE ENVÍO'), findsOneWidget);

    await tester.tap(find.text('+ Agregar zona'));
    await tester.pumpAndSettle();
    await tester.enterText(campo(const ValueKey('zona-nombre-0')), 'Centro');
    await tester.enterText(campo(const ValueKey('zona-costo-0')), '1500');
    await tester.enterText(campo(const ValueKey('zona-demora-0')), '15');
    await tester.tap(find.text('Adelantado'));
    await tester.tap(find.byKey(const Key('pedidos_automatica')));
    await tester.ensureVisible(find.byKey(const Key('pedidos_catalogo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pedidos_catalogo')));
    await tester.enterText(campo(const Key('pedidos_min_normal')), '25');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await esperar(tester);

    final c = (await tester.runAsync(() => configPedidosActual(db)))!;
    expect(c.formasDisponibles, [FormaEntrega.retiro, FormaEntrega.cadetePropio]);
    expect(c.zonas.single.nombre, 'Centro');
    expect(c.zonas.single.costoCentavos, 150000);
    expect(c.zonas.single.demoraExtraMin, 15);
    expect(c.pago, ModoPagoPedido.adelantado);
    expect(c.confirmacionAutomatica, isTrue);
    expect(c.catalogoWhatsapp, isTrue);
    expect(c.minutosNormal, 25);
    await tester.pump(const Duration(seconds: 3)); // que se vaya el aviso
  });

  testWidgets('no guarda un envío sin zonas ni un local sin ninguna entrega', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('pedidos_reparto')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await esperar(tester);
    expect(find.textContaining('al menos una zona'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pedidos_reparto')));
    await tester.tap(find.byKey(const Key('pedidos_retiro')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await esperar(tester);
    expect(find.textContaining('al menos una forma de entrega'), findsOneWidget);
    expect((await tester.runAsync(() => configPedidosActual(db)))!.retiro, isTrue, reason: 'no se guardó nada');
  });

  testWidgets('las comandas en la Point se prenden en este equipo al tocarlas, sin Guardar', (tester) async {
    final registro = RegistroComandasEnMemoria();
    final comandera = ComanderaPoint(db: db, registro: registro, imprimir: (_, {required idempotencyKey, required externalReference}) async {});
    await abrir(tester, comandera: comandera);
    expect(find.text('Imprimir las comandas en la terminal Point'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('pedidos_comandas_point')));
    await tester.tap(find.byKey(const Key('pedidos_comandas_point')));
    await esperar(tester);
    expect(registro.prendida, isTrue);
    expect(comandera.andando, isTrue);
    expect(find.textContaining('Prendelo en un solo equipo'), findsOneWidget);
    comandera.detener(); // su reintento de cada minuto es un Timer: el test no termina con uno vivo
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
