// Login del escritorio con la misma cuenta que la companion (Bruno,
// 2026-09-18: "mismo login... que abra una ventana en Chrome... y luego
// volver a la app"). `google_sign_in` no tiene implementación para Windows
// (su tabla de soporte oficial es Android/iOS/macOS/Web nada más) — se arma
// el flujo real de OAuth a mano: abrir el navegador del sistema, levantar un
// servidor HTTP efímero (mismo paquete `shelf` que ya usa
// `servidor_companion.dart` — Regla 3, no un mecanismo nuevo) para recibir
// el código de vuelta, canjearlo por tokens, y de ahí en más el ID token de
// Google se canjea por una sesión de Supabase (`signInWithIdToken`) — a
// diferencia de `firebase_auth`, el SDK de Supabase no tiene ningún bug de
// plataforma en Windows, así que no hace falta ningún camino REST paralelo
// (ver `ESTADO.md` para el porqué de la migración completa).
//
// Cliente OAuth "App de escritorio" (no un "Web client") — Google exige
// mandar también el `client_secret` en el canje de código para este tipo de
// cliente, aunque documenta que no se lo trata como secreto real para una
// app instalada (no hay forma de guardarlo bien en un `.exe` que se
// distribuye a mano). Se sigue usando el mismo cliente OAuth de siempre: el
// canje de código no depende de qué backend consume el ID token después.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Cliente OAuth "escritorio" de Google. No se versionan: se pasan al compilar
// (`flutter build windows --dart-define=GOOGLE_OAUTH_CLIENT_ID=... --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=...`).
// Sin ellos el inicio de sesión con Google de escritorio queda deshabilitado.
const _clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
const _clientSecret = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET');

class AutenticacionEscritorioException implements Exception {
  const AutenticacionEscritorioException(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Abre el navegador predeterminado para elegir la cuenta de Google, espera
/// el código de vuelta en un servidor local efímero, lo canjea por tokens, y
/// establece la sesión real (`firebase_rest_escritorio.dart`) con ellos.
/// Nunca deja el servidor HTTP colgado atrás (se cierra en el `finally`,
/// haya salido bien o mal).
Future<void> iniciarSesionConGoogleDesdeEscritorio({
  Duration timeout = const Duration(minutes: 3),
  http.Client? httpClienteDePrueba,
}) async {
  final verifier = _generarCadenaAleatoria(64);
  final challenge = _codeChallengeDe(verifier);
  // Protege contra que una respuesta de otro origen (otra pestaña, otro
  // proceso apuntando al mismo puerto) sea aceptada como si fuera la
  // nuestra — el callback la descarta si no coincide.
  final estadoEsperado = _generarCadenaAleatoria(16);

  final codigoCompleter = Completer<String>();

  final servidor = await shelf_io.serve((Request request) {
    final parametros = request.url.queryParameters;
    if (parametros['state'] != estadoEsperado) {
      return Response.forbidden('Estado inválido.');
    }
    if (!codigoCompleter.isCompleted) {
      final codigo = parametros['code'];
      if (codigo != null) {
        codigoCompleter.complete(codigo);
      } else {
        codigoCompleter.completeError(
          AutenticacionEscritorioException(
            'Google no devolvió un código (${parametros['error'] ?? "sin detalle"}).',
          ),
        );
      }
    }
    return Response.ok(
      '<html><body style="font-family: sans-serif; text-align: center; padding-top: 80px;">'
      '<h2>Listo — ya podés cerrar esta pestaña y volver a La Plazoleta.</h2>'
      '</body></html>',
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }, InternetAddress.loopbackIPv4, 0);

  try {
    final redirectUri = 'http://localhost:${servidor.port}';
    final urlAutorizacion = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': estadoEsperado,
      'prompt': 'select_account',
    });

    final abrio = await launchUrl(urlAutorizacion, mode: LaunchMode.externalApplication);
    if (!abrio) {
      throw const AutenticacionEscritorioException('No se pudo abrir el navegador.');
    }

    final codigo = await codigoCompleter.future.timeout(
      timeout,
      onTimeout: () => throw const AutenticacionEscritorioException(
        'Pasaron unos minutos sin completar el login en el navegador — probá de nuevo.',
      ),
    );

    final tokens = await _canjearCodigoPorTokens(
      codigo: codigo,
      redirectUri: redirectUri,
      verifier: verifier,
      cliente: httpClienteDePrueba,
    );
    final idToken = tokens['id_token'] as String?;
    if (idToken == null) {
      throw const AutenticacionEscritorioException('Google no devolvió un token válido — probá de nuevo.');
    }

    try {
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: tokens['access_token'] as String?,
      );
    } on AuthException catch (e) {
      throw AutenticacionEscritorioException(e.message);
    }
  } finally {
    await servidor.close(force: true);
  }
}

Future<Map<String, dynamic>> _canjearCodigoPorTokens({
  required String codigo,
  required String redirectUri,
  required String verifier,
  http.Client? cliente,
}) async {
  final http_ = cliente ?? http.Client();
  try {
    final respuesta = await http_.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'code': codigo,
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
    );
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw AutenticacionEscritorioException(
        'Google OAuth (${respuesta.statusCode}): ${cuerpo['error_description'] ?? cuerpo['error'] ?? respuesta.body}',
      );
    }
    return cuerpo;
  } finally {
    if (cliente == null) http_.close();
  }
}

String _generarCadenaAleatoria(int bytes) {
  final random = Random.secure();
  final valores = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(valores).replaceAll('=', '');
}

String _codeChallengeDe(String verifier) {
  final hash = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(hash.bytes).replaceAll('=', '');
}
