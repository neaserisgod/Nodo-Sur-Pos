import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:la_plazoleta/ui/tema/iconos.dart';

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
  testWidgets('editar el recargo de cigarrillos persiste el cambio', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.enterText(_campo('campo_primer_atado'), '500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.recargoPrimerAtadoCentavos, 50000);
  });

  testWidgets('navegar a Usuarios y agregar uno nuevo', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
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
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.text('Secciones del menú'));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    final secciones = await db.select(db.seccionesMenu).get();
    expect(secciones.first.visible, isFalse);
  });

  testWidgets('navegar a App companion y generar el código muestra el QR', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.tap(find.text('App companion (Android)'));
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

    // Dos QR desde 2026-09-07: el de emparejamiento (JSON) y el de
    // instalación para un celular nuevo (URL a /companion/apk, Bruno:
    // "que en la app escaneando el QR lo ponga para descargar").
    expect(find.byType(QrImageView), findsNWidgets(2));

    final config = await db.select(db.configuracionTabla).getSingle();
    expect(config.companionToken, isNotNull);
  });
}
