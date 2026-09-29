// Login de la companion (Google o registro por email/contraseña) — capa
// nueva delante de todo lo que ya existía (emparejamiento con la PC, elegir
// usuario de turno), sin tocarlos: fase 1 del rediseño "POS aparte" (Bruno,
// 2026-09-18: "login con Google o register"). Es una sola cuenta para todo
// el negocio — el selector de usuario/turno de `pantalla_elegir_usuario.dart`
// sigue siendo un concepto totalmente aparte, sin relación con esto.

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Único email autorizado a entrar a la companion (Bruno, 2026-09-18: "una
/// sola cuenta para todo"). Cambiarlo acá alcanza si el día de mañana se usa
/// otra cuenta — sin lista dinámica ni panel para esto a propósito, es un
/// negocio de una sola persona operando el celular.
const emailAutorizadoCompanion = 'gtalovergamer@gmail.com';

/// El cliente OAuth "web" del proyecto Firebase (`android/app/google-services.json`,
/// `oauth_client` con `client_type: 3`). Google Sign-In v7 lo necesita
/// explícito para emitir un idToken con la audiencia que Firebase espera —
/// antes de la v7 esto se resolvía solo, leyendo un recurso que generaba el
/// plugin de Gradle.
const _serverClientId = '341561955732-cptrnbmp7046psjga679od63aqvko8mu.apps.googleusercontent.com';

bool _googleSignInListo = false;

Future<void> _asegurarGoogleSignInListo() async {
  if (_googleSignInListo) return;
  await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
  _googleSignInListo = true;
}

/// true si [user] es la cuenta autorizada (ver [emailAutorizadoCompanion]) —
/// comparación por email nada más, sin importar mayúsculas.
bool esCuentaAutorizada(User? user) =>
    user != null && user.email?.toLowerCase() == emailAutorizadoCompanion.toLowerCase();

class AutenticacionCompanionException implements Exception {
  const AutenticacionCompanionException(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Abre el selector de cuenta de Google y firma en Supabase con la que se
/// elija. `null` si se canceló el selector — no es un error, la pantalla de
/// login se queda como está.
Future<AuthResponse?> iniciarSesionConGoogle() async {
  await _asegurarGoogleSignInListo();

  final GoogleSignInAccount cuenta;
  try {
    cuenta = await GoogleSignIn.instance.authenticate();
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    throw AutenticacionCompanionException('No se pudo abrir el selector de cuenta de Google (${e.code.name}).');
  }

  final idToken = cuenta.authentication.idToken;
  if (idToken == null) {
    throw const AutenticacionCompanionException('Google no devolvió un token válido — probá de nuevo.');
  }

  try {
    return await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  } on AuthException catch (e) {
    throw AutenticacionCompanionException(_mensajeDeErrorSupabase(e));
  }
}

Future<AuthResponse> registrarseConEmail(String email, String contrasena) async {
  try {
    return await Supabase.instance.client.auth.signUp(email: email.trim(), password: contrasena);
  } on AuthException catch (e) {
    throw AutenticacionCompanionException(_mensajeDeErrorSupabase(e));
  }
}

Future<AuthResponse> iniciarSesionConEmail(String email, String contrasena) async {
  try {
    return await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: contrasena,
    );
  } on AuthException catch (e) {
    throw AutenticacionCompanionException(_mensajeDeErrorSupabase(e));
  }
}

/// Cierra la sesión de Supabase y, si se había usado, la de Google Sign-In
/// (si no se cierra esta también, el próximo "Continuar con Google" reusa la
/// cuenta anterior sin preguntar — mal si esa cuenta fue la rechazada por no
/// ser la autorizada).
Future<void> cerrarSesionCompanion() async {
  await Supabase.instance.client.auth.signOut();
  if (_googleSignInListo) {
    await GoogleSignIn.instance.signOut();
  }
}

String _mensajeDeErrorSupabase(AuthException e) {
  switch (e.code) {
    case 'invalid_credentials':
      return 'Email o contraseña incorrectos.';
    case 'user_already_exists':
    case 'email_exists':
      return 'Ya existe una cuenta con ese email — probá iniciar sesión en vez de registrarte.';
    case 'weak_password':
      return 'La contraseña es demasiado débil (mínimo 6 caracteres).';
    case 'validation_failed':
      return 'Ese email no es válido.';
    default:
      return e.message;
  }
}
