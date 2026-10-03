import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:la_plazoleta/ui/tema/iconos.dart';
import '../../helpers/base_para_tests.dart';

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` fuera del `TextField`
/// (fija, no la flotante de Material) — cada campo que un test necesita
/// tocar tiene una `Key` propia en el widget que lo instancia.
Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaConfiguracion(db: db, usuarioId: 1)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('arranca en Negocio y muestra los cinco grupos', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    for (final g in ['negocio', 'cajaYCobros', 'productos', 'equiposYCuenta', 'apariencia']) {
      expect(find.byKey(Key('grupo_$g')), findsOneWidget, reason: g);
    }
    expect(find.byKey(const Key('pastilla_comercio')), findsOneWidget);
    expect(find.byKey(const Key('campo_nombre_comercio')), findsOneWidget);
  });

  testWidgets('editar el recargo de cigarrillos persiste el cambio', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_cajaYCobros')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pastilla_cigarrillos')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_primer_atado'), '500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.recargoPrimerAtadoCentavos, 50000);
  });

  testWidgets('navegar a Usuarios y agregar uno nuevo', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_nuevo_usuario'), 'Ayuda finde');
    await tester.tap(find.byIcon(IconosPlazoleta.add));
    await tester.pumpAndSettle();

    expect(find.text('Ayuda finde'), findsOneWidget);
  });

  testWidgets('ocultar una sección del menú apaga su switch', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_apariencia')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pastilla_menu')));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    final secciones = await db.select(db.seccionesMenu).get();
    expect(secciones.first.visible, isFalse);
  });

  testWidgets('en Celular, generar el código muestra 6 números de un solo uso y el QR para bajar la app', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_equiposYCuenta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pastilla_companion')));
    await tester.pumpAndSettle();

    // La IP de LAN se carga aparte (llamada real al sistema operativo, no
    // gatilla frames por sí sola) — un pump extra alcanza para que
    // termine antes de buscar el botón.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final generar = find.text('Generar código');
    if (generar.evaluate().isEmpty) {
      // Sin red conectada en la máquina que corre el test: no hay nada más
      // que probar acá, el mensaje de "no se encontró una red" ya cubre
      // ese caso por su cuenta.
      return;
    }

    await tester.tap(generar);
    await tester.pumpAndSettle();

    // Desde 2026-10-03 se empareja con un código de 6 números (ya no con un QR con la llave); queda solo el QR
    // para bajar la app con la cámara.
    final codigo = tester.widget<Text>(find.byKey(const Key('codigo_emparejamiento'))).data!;
    expect(codigo, matches(RegExp(r'^\d{3} \d{3}$')));
    expect(find.byType(QrImageView), findsOneWidget);

    final config = await db.select(db.configuracionTabla).getSingle();
    expect(config.companionToken, isNotNull);
  });
}
