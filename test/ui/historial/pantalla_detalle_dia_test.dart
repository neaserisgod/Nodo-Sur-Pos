import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/historial/pantalla_detalle_dia.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

import '../../helpers/planilla_fixture.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  testWidgets('muestra las ventas del día y permite ir a editar una', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 0,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 50000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g')],
      renglonesMp: const [],
      gastos: const [],
    );

    // El piso de pantalla que soporta la app (CLAUDE.md, hardware).
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaDetalleDia(db: db, sesionId: sesionId, usuarioId: usuarioId)),
    );
    await tester.pumpAndSettle();

    // Una fila por venta, con su número y sus acciones.
    expect(find.byTooltip('Reimprimir'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Editar venta #'), findsOneWidget);
  });

  testWidgets('sin carpeta de tickets configurada, generar PDF pregunta la carpeta en vez de solo avisar', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 0,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 0,
      mpContadoCentavos: 0,
      renglonesEfectivo: const [],
      renglonesMp: const [],
      gastos: const [],
    );

    // El piso de pantalla que soporta la app (CLAUDE.md, hardware).
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaDetalleDia(db: db, sesionId: sesionId, usuarioId: usuarioId)),
    );
    await tester.pumpAndSettle();

    // Bug real reportado por el dueño: "doy a imprimir y no sale nada de
    // seleccionar" — antes esto solo mostraba un SnackBar mandando a
    // configurar la carpeta en la pantalla de Impresión. Ahora pregunta la
    // carpeta ahí mismo (`getDirectoryPath()`, no probable en un
    // `testWidgets` real — en este entorno vuelve `null` sin bloquear,
    // como si el usuario hubiera cancelado el selector); lo único que este
    // test puede confirmar acá es que tocar el botón sin carpeta configurada
    // ya no crashea ni deja la pantalla en un estado raro.
    await tester.tap(find.text('Generar PDF'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Generar PDF'), findsOneWidget);
  });
}
