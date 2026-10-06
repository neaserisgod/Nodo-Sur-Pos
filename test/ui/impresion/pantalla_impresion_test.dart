// Igual que en respaldo: acá solo se prueban interacciones que no tocan
// disco ni red real (ambas cosas se cuelgan o no corresponden dentro de
// testWidgets en este entorno). La cobertura de red/disco está en
// impresion_controlador_test.dart con test() plano.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/kit/kit.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/impresion/pantalla_impresion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` fuera del `TextField`
/// (fija, no la flotante de Material) — cada campo que un test necesita
/// tocar tiene una `Key` propia en el widget que lo instancia.
Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // 1000px ya no alcanza con la barra lateral del kit sumada a las dos
  // columnas de esta pantalla — 1920×1080 es el objetivo de diseño real
  // (CLAUDE.md, fase 13).
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: Scaffold(body: SingleChildScrollView(child: ContenidoImpresion(db: db, usuarioId: 1)))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin nada configurado: ticket de prueba deshabilitado, avisa que falta carpeta', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);

    expect(tester.widget<Btn>(find.byKey(const Key('boton_ticket_prueba'))).onTap, isNull);
    expect(find.text('Sin carpeta configurada'), findsOneWidget);
  });

  testWidgets('cargar access token y terminal id habilita el ticket de prueba', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);

    await _pump(tester, db);
    await tester.enterText(_campo('campo_mp_token'), 'TOKEN-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_mp_terminal'), 'TERM-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.widget<Btn>(find.byKey(const Key('boton_ticket_prueba'))).onTap, isNotNull);
  });

  testWidgets('buscar por número de venta lista solo esa venta', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 1000, totalCentavos: 1000),
        );
    final ventaId2 = await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 2000, totalCentavos: 2000),
        );

    await _pump(tester, db);
    expect(find.textContaining('Venta #'), findsNWidgets(2));

    await tester.enterText(_campo('campo_numero_venta'), ventaId2.toString());
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Venta #$ventaId2'), findsOneWidget);
    expect(find.textContaining('Venta #'), findsOneWidget);
  });

  testWidgets('"Guardar PDF" queda habilitado aunque la carpeta de tickets no esté configurada', (tester) async {
    // Bug real reportado por el dueño: "doy a imprimir y no sale nada de
    // seleccionar" — el botón quedaba deshabilitado en silencio si no había
    // carpeta configurada, sin ningún aviso ni forma de arreglarlo desde
    // acá. Ahora, al tocarlo, pregunta la carpeta ahí mismo (no se puede
    // probar el toque en sí en un test — `getDirectoryPath()` real se
    // cuelga en `testWidgets`, ver encabezado de este archivo — solo que
    // el botón ya no está deshabilitado de entrada).
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 1000, totalCentavos: 1000),
        );

    await _pump(tester, db);
    expect(find.text('Sin carpeta configurada'), findsOneWidget);

    expect(tester.widget<Btn>(find.widgetWithText(Btn, 'Guardar PDF')).onTap, isNotNull);
  });
}
