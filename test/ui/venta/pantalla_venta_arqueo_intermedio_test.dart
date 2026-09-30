// Arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12; ya no bloqueante,
// El dueño 2026-09-15): un aviso dentro de la misma sesión, sin cortarla ni
// impedir seguir vendiendo — distinto de "Cerrar caja"/"Cambiar de turno".

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // El viewport de test por defecto (800×600) es más chico que el piso real
  // de la app (1366×768 desde la fase 13) — se fija acá, mismo criterio que
  // el resto de los tests de esta pantalla (ver TRAMPAS.md).
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      navigatorObservers: [routeObserver],
      home: PantallaVenta(db: db),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  testWidgets('sesión recién abierta: no pide arqueo todavía', (tester) async {
    await db
        .into(db.sesionesDeCaja)
        .insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
          ),
        );

    await _pump(tester, db);

    expect(find.textContaining('Pasaron 2 horas'), findsNothing);
  });

  testWidgets(
    'pasadas las 2hs de la apertura, avisa sin bloquear la venta',
    (tester) async {
      await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
              fechaApertura: Value(
                DateTime.now().subtract(const Duration(hours: 3)),
              ),
            ),
          );

      await _pump(tester, db);

      // El aviso ya no es un banner siempre visible (El dueño, tercera pasada
      // de venta: "UN APARTADO NOTIFICACIONES") — vive detrás de la
      // campanita de la franja superior, hay que abrirla primero.
      await tester.tap(find.byTooltip('Notificaciones'));
      await tester.pump();

      expect(find.textContaining('Pasaron 2 horas'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Hacer arqueo'), findsOneWidget);
      // A diferencia de los otros dos bloqueos de esta pantalla (sin sesión
      // / sesión de otro día), esto es solo un aviso: se sigue vendiendo con
      // el campo de búsqueda visible al mismo tiempo.
      expect(find.byTooltip('Cambiar de sección'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    },
  );

  testWidgets(
    'completar el arqueo hace desaparecer el aviso sin cortar ni cerrar la sesión',
    (tester) async {
      final sesionId = await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 500000,
              fechaApertura: Value(
                DateTime.now().subtract(const Duration(hours: 3)),
              ),
            ),
          );

      await _pump(tester, db);

      // Mismo motivo que el test anterior: el aviso vive detrás de la
      // campanita, hay que abrirla antes de poder tocar "Hacer arqueo".
      await tester.tap(find.byTooltip('Notificaciones'));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Hacer arqueo'));
      await tester.pumpAndSettle();

      // Por key, no `.first`: a diferencia de cuando esto bloqueaba, ahora
      // el campo único de búsqueda sigue en pantalla detrás del modal, así
      // que también hay un `TextField` fuera del diálogo.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('campo_efectivo_contado_intermedio')),
          matching: find.byType(TextField),
        ),
        '5.000',
      );
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('campo_mp_contado_intermedio')),
          matching: find.byType(TextField),
        ),
        '0',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('campo_lata_contada_intermedio')),
          matching: find.byType(TextField),
        ),
        '0',
      );
      await tester.tap(find.text('Confirmar arqueo'));
      await tester.pumpAndSettle();

      // El aviso desaparece — la venta nunca dejó de estar disponible.
      expect(find.textContaining('Pasaron 2 horas'), findsNothing);

      // La sesión sigue siendo la misma sesión abierta — nada se cortó.
      final sesion = await (db.select(
        db.sesionesDeCaja,
      )..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'ABIERTA');

      final arqueos = await db.select(db.arqueosIntermedios).get();
      expect(arqueos, hasLength(1));
      expect(arqueos.single.sesionCajaId, sesionId);
      expect(arqueos.single.efectivoContadoCentavos, 500000);
    },
  );
}
