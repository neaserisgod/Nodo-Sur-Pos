// Entrar con la cuenta de Google del teléfono, con el selector de Android, sin abrir el navegador (El dueño, 2026-10-13: "la
// vinculación por el sitio es un paso medio innecesario"). Acá solo se consigue el id_token de la cuenta elegida; quién es y
// dónde trabaja lo decide el sitio (`POST /api/device/google`).
//
// Para que Google lo permita, la app tiene que estar registrada en Google Cloud (cliente OAuth tipo Android, con el paquete y
// la huella de la clave que firma el APK). Mientras no lo esté, Google contesta con un error o como si se hubiera cancelado:
// por eso la pantalla de entrar siempre deja la salida por el navegador.

import 'package:google_sign_in/google_sign_in.dart';

/// Pide una cuenta de Google y devuelve su id_token para [serverClientId] (el client ID Web del sitio). Null si la persona
/// cerró el selector sin elegir.
typedef PedirCuentaGoogle = Future<String?> Function(String serverClientId);

/// El teléfono o el sitio no permiten entrar con Google desde la app: se entra por el navegador.
class GoogleNoDisponible implements Exception {
  const GoogleNoDisponible(this.detalle);
  final String detalle;
  @override
  String toString() => 'No se pudo entrar con Google desde la app ($detalle).';
}

Future<void>? _inicializado;

Future<String?> pedirCuentaGoogleDelTelefono(String serverClientId) async {
  final google = GoogleSignIn.instance;
  try {
    await (_inicializado ??= google.initialize(serverClientId: serverClientId));
  } catch (e) {
    // Que una falla al inicializar no quede guardada: el próximo toque vuelve a intentar.
    _inicializado = null;
    throw GoogleNoDisponible(e is GoogleSignInException ? (e.description ?? e.code.name) : '$e');
  }
  try {
    if (!google.supportsAuthenticate()) throw const GoogleNoDisponible('el teléfono no lo permite');
    // Siempre la lista de cuentas: en un teléfono con varias se elige cada vez, nunca se entra solo con la última usada.
    // Si cerrar la sesión anterior falla, igual se pide la cuenta.
    try {
      await google.signOut();
    } catch (_) {}
    final cuenta = await google.authenticate();
    final idToken = cuenta.authentication.idToken;
    if (idToken == null || idToken.isEmpty) throw const GoogleNoDisponible('Google no devolvió la cuenta');
    return idToken;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    if (e.code == GoogleSignInExceptionCode.clientConfigurationError || e.code == GoogleSignInExceptionCode.providerConfigurationError) {
      _inicializado = null;
    }
    throw GoogleNoDisponible(e.description ?? e.code.name);
  } on GoogleNoDisponible {
    rethrow;
  } catch (e) {
    // Cualquier otra cosa del lado de Android (un PlatformException, por ejemplo): se ofrece el navegador, nunca queda trabado.
    throw GoogleNoDisponible('$e');
  }
}
