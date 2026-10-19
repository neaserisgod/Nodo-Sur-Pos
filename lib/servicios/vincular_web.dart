// Entrar con Google desde Nodo Sur Servicios en el navegador (`docs/PLAN-WEB-SERVICIOS.md`). Es la misma vinculación de la PC y
// el celular (página /vincular/ del sitio, PKCE), pero sin servidor local: la app guarda el verificador, se va a /vincular/ en la
// misma pestaña y el sitio la devuelve a /app/?code=…&state=…; al volver a cargar, la app canjea el código y queda vinculada.

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/vinculacion.dart';
import '../edicion.dart' show edicionActual;
import 'cuenta_nube.dart';
import 'limpiar_url.dart';

const _clavePendiente = 'nodosur_vinculacion_web';

/// Se va a la página de vinculación (en la misma pestaña). No vuelve: la app se carga de nuevo al terminar.
Future<Never> empezarVinculacionWeb({required String idDispositivo, required String nombre}) async {
  final verificador = generarVerificador();
  final state = generarState();
  await (await SharedPreferences.getInstance()).setString(_clavePendiente, jsonEncode({'state': state, 'verificador': verificador}));
  final url = urlVincularWeb(base: Uri.base, state: state, desafio: desafioDe(verificador), idDispositivo: idDispositivo, nombre: nombre, edicion: edicionActual.name);
  if (!await launchUrl(url, webOnlyWindowName: '_self')) {
    throw const ErrorNube('sin_navegador', 'No se pudo abrir la página para entrar.');
  }
  return Completer<Never>().future; // la pestaña ya se está yendo
}

/// Si la app se cargó volviendo de la vinculación, canjea el código, guarda la cuenta y limpia la dirección. Devuelve la cuenta, o
/// null si no había nada que terminar. Lanza [ErrorNube] si el sitio rechaza el código (vencido o ya usado: se vuelve a entrar).
Future<CuentaVinculada?> terminarVinculacionWeb({
  required Uri url,
  required ClienteNube cliente,
  required AlmacenCuenta almacen,
  required String nombre,
}) async {
  if (!url.queryParameters.containsKey('code')) return null;
  final prefs = await SharedPreferences.getInstance();
  final crudo = prefs.getString(_clavePendiente);
  await prefs.remove(_clavePendiente); // de un solo uso, salga bien o mal
  limpiarDireccion(); // el código no queda en la barra ni en el historial
  if (crudo == null) return null;
  final pendiente = jsonDecode(crudo) as Map<String, dynamic>;
  final code = codigoDeVueltaWeb(url, stateEsperado: pendiente['state'] as String);
  if (code == null) return null;
  final cuenta = await cliente.canjear(code: code, verificador: pendiente['verificador'] as String, nombre: nombre);
  await almacen.guardar(cuenta);
  return cuenta;
}
