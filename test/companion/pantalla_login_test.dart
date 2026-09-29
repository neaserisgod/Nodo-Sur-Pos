// Fase 1 del rediseño "POS aparte" (Bruno, 2026-09-18: "login con Google o
// register"). El cliente real de Supabase nunca se llama acá — las acciones
// se inyectan (mismo patrón `DePrueba` que `resolverServicioCompanion`,
// `ImpresionControlador`), y las respuestas se simulan con mocktail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/autenticacion.dart';
import 'package:la_plazoleta/companion/pantalla_login.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockAuthResponse extends Mock implements AuthResponse {}

class _MockUser extends Mock implements User {}

AuthResponse _credencialCon(String email) {
  final user = _MockUser();
  when(() => user.email).thenReturn(email);
  final credencial = _MockAuthResponse();
  when(() => credencial.user).thenReturn(user);
  return credencial;
}

Future<void> _pump(
  WidgetTester tester, {
  Future<AuthResponse?> Function()? google,
  Future<AuthResponse> Function(String, String)? registrar,
  Future<AuthResponse> Function(String, String)? iniciar,
  Future<void> Function()? cerrarSesion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaLogin(
        iniciarSesionConGoogleDePrueba: google,
        registrarseConEmailDePrueba: registrar,
        iniciarSesionConEmailDePrueba: iniciar,
        cerrarSesionDePrueba: cerrarSesion,
      ),
    ),
  );
}

void main() {
  group('PantallaLogin', () {
    testWidgets('Google con la cuenta autorizada no muestra ningún error', (tester) async {
      await _pump(
        tester,
        google: () async => _credencialCon(emailAutorizadoCompanion),
      );

      await tester.tap(find.text('Continuar con Google'));
      // Ni bien la cuenta es la autorizada, `PantallaLogin` deja de tocar su
      // propio estado a propósito (comentario en `_tras`): en la app real la
      // reemplaza `PuertaDeEntradaCompanion` apenas emite el nuevo user, así
      // que el botón de email se queda con su spinner puesto para siempre —
      // acá no hay quien la reemplace, por eso ningún `pumpAndSettle` (el
      // spinner nunca deja de animar).
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('no está autorizada'), findsNothing);
    });

    testWidgets('Google con una cuenta distinta a la autorizada avisa y cierra la sesión', (tester) async {
      var sesionCerrada = false;
      await _pump(
        tester,
        google: () async => _credencialCon('otra.cuenta@gmail.com'),
        cerrarSesion: () async => sesionCerrada = true,
      );

      await tester.tap(find.text('Continuar con Google'));
      await tester.pumpAndSettle();

      expect(find.text('Esa cuenta no está autorizada para usar la companion.'), findsOneWidget);
      expect(sesionCerrada, isTrue);
      // Vuelve a poder tocarse — no se queda trabada en "procesando".
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('cancelar el selector de Google no muestra ningún error', (tester) async {
      await _pump(tester, google: () async => null);

      await tester.tap(find.text('Continuar con Google'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no está autorizada'), findsNothing);
      expect(find.text('Algo salió mal'), findsNothing);
    });

    testWidgets('registrarse con una contraseña débil muestra el error de Supabase', (tester) async {
      await _pump(
        tester,
        registrar: (_, _) async => throw const AutenticacionCompanionException(
          'La contraseña es demasiado débil (mínimo 6 caracteres).',
        ),
      );

      // Pasa a modo "registrarme".
      await tester.tap(find.text('¿No tenés cuenta? Registrarme'));
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'bruno@laplazoleta.com');
      await tester.enterText(find.widgetWithText(TextField, 'Contraseña'), '123');
      await tester.tap(find.text('Registrarme'));
      await tester.pumpAndSettle();

      expect(find.text('La contraseña es demasiado débil (mínimo 6 caracteres).'), findsOneWidget);
    });

    testWidgets('iniciar sesión con campos vacíos avisa sin llamar a Supabase', (tester) async {
      var llamado = false;
      await _pump(tester, iniciar: (_, _) async {
        llamado = true;
        return _credencialCon(emailAutorizadoCompanion);
      });

      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();

      expect(find.text('Completá el email y la contraseña.'), findsOneWidget);
      expect(llamado, isFalse);
    });

    testWidgets('email/contraseña con la cuenta autorizada no muestra ningún error', (tester) async {
      await _pump(
        tester,
        iniciar: (email, contrasena) async => _credencialCon(emailAutorizadoCompanion),
      );

      await tester.enterText(find.widgetWithText(TextField, 'Email'), emailAutorizadoCompanion);
      await tester.enterText(find.widgetWithText(TextField, 'Contraseña'), 'unaClaveSegura');
      await tester.tap(find.text('Iniciar sesión'));
      // Ver el comentario del test de Google con la cuenta autorizada: sin
      // `pumpAndSettle`, el spinner del botón se queda animando a propósito.
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('no está autorizada'), findsNothing);
      expect(find.text('Completá el email y la contraseña.'), findsNothing);
    });
  });
}
