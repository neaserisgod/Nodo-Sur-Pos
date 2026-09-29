// Fase 1 del rediseño "POS aparte" (Bruno, 2026-09-18): sin sesión de la
// cuenta autorizada, la companion no puede llegar a ninguna otra pantalla.
// El stream de `onAuthStateChange` se reemplaza por uno falso — nunca se
// toca el cliente real de Supabase acá.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/autenticacion.dart';
import 'package:la_plazoleta/companion/companion_app.dart';
import 'package:la_plazoleta/companion/pantalla_login.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockUser extends Mock implements User {}

Future<void> _pump(WidgetTester tester, Stream<User?> authState) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaCompanion.claro,
      // `iniciarSyncSupabaseDePrueba: false`: sin esto, llegar a
      // `_PantallaInicial` (cuenta autorizada) abriría la base local de
      // verdad y arrancaría `SincronizacionSupabase` contra el cliente real
      // de Supabase, que no existe en este entorno de test.
      home: PuertaDeEntradaCompanion(authStateDePrueba: authState, iniciarSyncSupabaseDePrueba: false),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PuertaDeEntradaCompanion', () {
    testWidgets('mientras el stream no emitió nada todavía, muestra un spinner y no la companion', (tester) async {
      // Un stream ya cerrado (`Stream.empty()`) no sirve para simular esto:
      // pasa a `ConnectionState.done` sin datos, no se queda en `waiting`. Un
      // `StreamController` sin cerrar sí se queda esperando, como
      // `authStateChanges()` real antes de la primera emisión.
      final controlador = StreamController<User?>();
      addTearDown(controlador.close);
      await _pump(tester, controlador.stream);
      await tester.pump();

      expect(find.byType(PantallaLogin), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('sin sesión (null), muestra el login', (tester) async {
      await _pump(tester, Stream<User?>.value(null));
      await tester.pump();

      expect(find.byType(PantallaLogin), findsOneWidget);
    });

    testWidgets('con una cuenta que no es la autorizada, muestra el login', (tester) async {
      final user = _MockUser();
      when(() => user.email).thenReturn('otra.cuenta@gmail.com');

      await _pump(tester, Stream<User?>.value(user));
      await tester.pump();

      expect(find.byType(PantallaLogin), findsOneWidget);
    });

    testWidgets('con la cuenta autorizada, deja de mostrar el login', (tester) async {
      final user = _MockUser();
      when(() => user.email).thenReturn(emailAutorizadoCompanion);

      await _pump(tester, Stream<User?>.value(user));
      await tester.pump();

      expect(find.byType(PantallaLogin), findsNothing);
    });
  });
}
