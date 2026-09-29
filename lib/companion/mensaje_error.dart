// Traduce una excepción técnica a algo legible para quien atiende el
// mostrador — sin esto, el error más común de la companion (WiFi débil, la
// PC apagada o dormida) se mostraba tal cual la excepción cruda,
// técnica y en inglés ("SocketException: Failed host lookup..."). Un solo
// lugar (Regla 3) en vez de que cada pantalla decida su propio mensaje.
import 'dart:async';
import 'dart:io';

import 'cliente_companion.dart';

String mensajeDeError(Object error) {
  // El servidor ya arma un mensaje legible en español (ver
  // `ClienteCompanion._revisar`) — se muestra tal cual.
  if (error is ErrorCompanion) return error.mensaje;
  if (error is SocketException || error is HttpException) {
    return 'No se pudo conectar con la PC — revisá que esté prendida, '
        'con la app abierta, y que el celular esté en la misma WiFi.';
  }
  if (error is TimeoutException) {
    return 'La PC tardó demasiado en responder — probá de nuevo.';
  }
  if (error is FormatException) {
    return 'La PC devolvió algo que la app no pudo entender.';
  }
  return '$error';
}
