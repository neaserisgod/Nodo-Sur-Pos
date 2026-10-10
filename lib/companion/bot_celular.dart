// El bot de WhatsApp desde este celular (`docs/PLAN-BOT.md`): el acceso al sitio con la cuenta vinculada y si el negocio tiene
// el bot, para mostrar o no su pantalla en Más.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/bot_whatsapp.dart';
import '../servicios/acceso_bot.dart';
import '../servicios/push.dart';
import '../servicios/cuenta_nube.dart' show AlmacenCuenta, AlmacenCuentaEnArchivo, ClienteNube;

final _clienteNubeBot = ClienteNube(http: http.Client());

/// El acceso al bot con la cuenta vinculada de este celular (el mismo archivo de cuenta que la sync y la IA).
final AccesoBot accesoBotDelCelular = AccesoBotNube(() async {
  final soporte = await getApplicationSupportDirectory();
  return (almacen: AlmacenCuentaEnArchivo(soporte.path) as AlmacenCuenta, cliente: _clienteNubeBot);
});

/// Lo último que dijo el sitio del bot (null = todavía no se preguntó, o el equipo no está vinculado). Más lo escucha para
/// mostrar la fila "Bot de WhatsApp" solo si el negocio lo tiene.
final ValueNotifier<EstadoBot?> estadoBotCelular = ValueNotifier<EstadoBot?>(null);

DateTime? _preguntado;

/// Pregunta de nuevo, como mucho una vez cada 10 minutos (economía de Cloudflare). Nunca tira: sin red queda lo último.
Future<void> refrescarEstadoBot({AccesoBot? acceso, bool forzar = false}) async {
  final ahora = DateTime.now();
  if (!forzar && _preguntado != null && ahora.difference(_preguntado!) < const Duration(minutes: 10)) return;
  _preguntado = ahora;
  try {
    estadoBotCelular.value = await (acceso ?? accesoBotDelCelular).estado();
  } catch (_) {
    // Sin red o sin plan: queda lo que había.
  }
}

RegistroPush? _push;

/// Registra el token de notificaciones de este celular en el sitio (una vez por sesión, `push.dart`), con la cuenta vinculada:
/// también en "PC y celular", donde la sync la sube la PC. Nunca tira.
Future<void> registrarPushDelCelular() async {
  try {
    final soporte = await getApplicationSupportDirectory();
    final cuenta = await AlmacenCuentaEnArchivo(soporte.path).leer();
    if (cuenta == null) return;
    await (_push ??= RegistroPush(cliente: _clienteNubeBot)).registrarSiHaceFalta(cuenta.token);
  } catch (_) {
    // Sin cuenta o sin red: la próxima vez que se abra el menú.
  }
}
