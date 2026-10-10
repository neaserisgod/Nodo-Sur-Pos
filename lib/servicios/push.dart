// Notificaciones con la app cerrada (Firebase Cloud Messaging; en el sitio, `functions/_lib/push.js`): un pedido o un turno nuevo
// del bot de WhatsApp le llega al celular del local aunque la app no esté abierta.
//
// Solo en Android, por un canal propio (`MainActivity.kt`) y no con los plugins de Firebase para Flutter: el de Windows baja el SDK
// de Firebase para C++ al compilar la PC, que no lo usa. El celular saca su token y lo registra en el sitio con la cuenta
// vinculada; el sitio manda la notificación y Android la muestra solo.
//
// Sin [opcionesFirebase] cargadas (los datos del `google-services.json` del proyecto de Firebase de Nodo Sur) no hace nada.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../edicion.dart';
import 'cuenta_nube.dart';

/// Los datos públicos del proyecto de Firebase (del `google-services.json`: `current_key`, `mobilesdk_app_id`, `project_number`,
/// `project_id`). No son secretos: identifican la app ante Firebase. Vacíos = sin notificaciones todavía.
class OpcionesFirebase {
  const OpcionesFirebase({required this.apiKey, required this.appId, required this.senderId, required this.projectId});
  final String apiKey;
  final String appId;
  final String senderId;
  final String projectId;

  bool get cargadas => apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty;

  Map<String, String> toJson() => {'apiKey': apiKey, 'appId': appId, 'senderId': senderId, 'projectId': projectId};
}

// Proyecto "Nodo Sur" de Firebase (El dueño, 2026-10-10), app Android `com.laplazoleta.companion`.
const opcionesFirebase = OpcionesFirebase(
  apiKey: 'AIzaSyDKTQ9qM53kwrpu-T2KHLiXQtLrT2L6roI',
  appId: '1:831126263942:android:909951cf843fc985a81907',
  senderId: '831126263942',
  projectId: 'nodo-sur-eb45a',
);

// Nodo Sur Servicios es otra app para Firebase (otro applicationId, `com.laplazoleta.servicios`): tiene su propio id de app en el
// mismo proyecto (el `mobilesdk_app_id` de su google-services.json, El dueño, 2026-10-10).
const _appIdServicios = '1:831126263942:android:212f489bb142cb40a81907';
OpcionesFirebase get opcionesFirebaseDeEdicion => esEdicionServicios
    ? OpcionesFirebase(apiKey: opcionesFirebase.apiKey, appId: _appIdServicios, senderId: opcionesFirebase.senderId, projectId: opcionesFirebase.projectId)
    : opcionesFirebase;

const _canal = MethodChannel('nodosur/push');

/// Registra el token de este celular en el sitio, una vez por sesión de la app (y otra vez si cambió). Nunca tira.
class RegistroPush {
  RegistroPush({required this.cliente, OpcionesFirebase? opciones, MethodChannel? canal, bool? esAndroid})
      : opciones = opciones ?? opcionesFirebaseDeEdicion,
        _canal2 = canal ?? _canal,
        _esAndroid = esAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final ClienteNube cliente;
  final OpcionesFirebase opciones;
  final MethodChannel _canal2;
  final bool _esAndroid;
  String? _registrado;
  bool _permisoPedido = false;

  Future<bool> registrarSiHaceFalta(String tokenCuenta) async {
    if (!_esAndroid || !opciones.cargadas) return false;
    try {
      if (!_permisoPedido) {
        _permisoPedido = true;
        await _canal2.invokeMethod<void>('pedirPermiso');
      }
      final token = await _canal2.invokeMethod<String>('token', opciones.toJson());
      if (token == null || token.isEmpty || token == _registrado) return false;
      await cliente.registrarPush(tokenCuenta, token);
      _registrado = token;
      return true;
    } catch (_) {
      return false; // sin Google Play Services, sin red: en la próxima vuelta
    }
  }
}
