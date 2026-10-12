// El bot de WhatsApp desde este celular (`docs/PLAN-BOT.md`): el acceso al sitio con la cuenta vinculada y si el negocio tiene
// el bot, para mostrar o no su pantalla en Más.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/bot_whatsapp.dart';
import '../edicion.dart';
import '../servicios/acceso_bot.dart';
import '../servicios/bot_en_celular.dart';
import '../servicios/push.dart';
import '../servicios/cuenta_nube.dart' show ClienteNube;
import '../servicios/almacenes_del_equipo.dart';
import '../plataforma.dart';

final _clienteNubeBot = ClienteNube(http: http.Client());

/// El acceso al bot con la cuenta vinculada de este celular (el mismo archivo de cuenta que la sync y la IA).
final AccesoBot accesoBotDelCelular = AccesoBotNube(() async => (almacen: await almacenCuentaDelEquipo(), cliente: _clienteNubeBot));

/// El bot que corre adentro de este celular (solo Nodo Sur Servicios trae Node; en la otra app no se usa).
final BotEnCelular botDelCelular = BotEnCelular(acceso: accesoBotDelCelular);

/// Al abrir Nodo Sur Servicios en Android: el bot encendido pasa a la versión que trae la app (`BotEnCelular.ponerAlDia`).
Future<void> ponerAlDiaElBotDelCelular() async {
  if (!esEdicionServicios || !esAndroid) return;
  await botDelCelular.ponerAlDia();
}

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
    final cuenta = await (await almacenCuentaDelEquipo()).leer();
    if (cuenta == null) return;
    await (_push ??= RegistroPush(cliente: _clienteNubeBot)).registrarSiHaceFalta(cuenta.token);
  } catch (_) {
    // Sin cuenta o sin red: la próxima vez que se abra el menú.
  }
}
