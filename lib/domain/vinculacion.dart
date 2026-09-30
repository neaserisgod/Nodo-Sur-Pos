// Vincular esta PC a la cuenta de Nodo Sur (como "iniciar sesión en el navegador"): la parte pura. La app abre
// el sitio con un desafío (PKCE), la persona entra con Google y confirma, el sitio devuelve un código de un
// solo uso a un servidor local (127.0.0.1) y la app lo canjea demostrando que es la misma que lo pidió.
// Los formatos son los que valida el sitio (`functions/_lib/devices.js`): si cambian allá, cambian acá.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const String hostNodoSur = 'horsepos.com';

/// base64url sin relleno.
String base64UrlSinRelleno(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String _aleatorio(int bytes) {
  final r = Random.secure();
  return base64UrlSinRelleno(List<int>.generate(bytes, (_) => r.nextInt(256)));
}

/// Verificador PKCE: 64 caracteres (el sitio acepta de 43 a 128).
String generarVerificador() => _aleatorio(48);

/// Desafío PKCE: SHA-256 del verificador en base64url sin relleno (43 caracteres).
String desafioDe(String verificador) => base64UrlSinRelleno(sha256.convert(ascii.encode(verificador)).bytes);

/// Valor de `state`, para reconocer que la respuesta es de esta vinculación (el sitio acepta 16 a 128).
String generarState() => _aleatorio(24);

/// Dirección que se abre en el navegador.
Uri urlVincular({
  required int puerto,
  required String state,
  required String desafio,
  required String idDispositivo,
  required String nombre,
  String host = hostNodoSur,
}) => Uri(
  scheme: 'https',
  host: host,
  path: '/vincular/',
  queryParameters: {
    'port': '$puerto',
    'state': state,
    'challenge': desafio,
    'device': idDispositivo,
    'name': nombre,
  },
);

/// Lo que llega al servidor local: `/callback?code=…&state=…`. Null si no es una respuesta válida de esta
/// vinculación (otro `state`, sin código o sin la ruta esperada).
String? codigoDeCallback(Uri pedido, {required String stateEsperado}) {
  if (pedido.path != '/callback') return null;
  final state = pedido.queryParameters['state'];
  final code = pedido.queryParameters['code'];
  if (state == null || state != stateEsperado) return null;
  if (code == null || code.isEmpty) return null;
  return code;
}
