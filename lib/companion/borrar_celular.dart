// "Cerrar sesión y borrar este celular" (El dueño, 2026-10-10: "no se puede cerrar sesión y eliminar los datos de la
// aplicación sin tener que borrarlos desde configuraciones" de Android). Borra la cuenta ACTIVA: la base local, la cuenta
// vinculada, el estado de la sync, el perfil, el modo de uso, la PC emparejada y sus preferencias.
//
// Con varias cuentas en el celular (2026-10-13, `cuentas_del_celular.dart`), las OTRAS no se tocan: después de borrar se
// trae la última usada. Sin otras, queda como recién instalado.
//
// Lo que ya subió a la nube (o está en la PC) no se toca: entrando de nuevo con la misma cuenta vuelve a bajar. Lo que
// no subió todavía se pierde, y la pantalla lo avisa antes.
//
// Después de borrar, la app vuelve a empezar sin cerrarse (`reinicio_companion.dart`): frena y olvida cada pieza que vive en
// memoria mientras la app está abierta (la base abierta, la sync, la escucha de la PC, la clave de la IA) y arma todo de cero.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cuentas_del_celular.dart';
import 'base_local.dart';
import 'borrar_base_navegador.dart';
import 'bot_celular.dart';
import '../servicios/registro_errores.dart';
import 'comandera.dart' show soltarComandera;
import 'cuentas_del_celular.dart';
import 'escucha_pc.dart';
import 'sync_nube_companion.dart';

/// Frena todo lo que escribe en la base o en la carpeta de datos, para poder borrarlas o moverlas: si la sync baja algo
/// mientras tanto, la base vuelve a aparecer a medias. Las piezas se sueltan (quedan en null): la cuenta que venga arma las
/// suyas. La base queda bloqueada hasta que termine el cambio (`desbloquearBaseLocal`).
///
/// Cada pieza se frena por separado: que una falle no deja a las otras andando.
Future<void> frenarLoQueEscribe() async {
  Future<void> frenar(String que, FutureOr<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      await registrarError('Frenar $que para cambiar de cuenta', e, st);
    }
  }

  final sync = syncNubeCompanion;
  syncNubeCompanion = null;
  await frenar('la sync', () async {
    if (sync == null) return;
    sync.conmutador.apagar(); // si no, una espera de traspaso la vuelve a prender
    sync.servicio.detener();
    // Una vuelta a medias todavía escribe su registro en la carpeta de datos: si terminara después de traer el otro negocio,
    // caería en el suyo. Se la espera (con tope: sin red puede tardar; con la base cerrada, igual falla al escribir).
    final hasta = DateTime.now().add(const Duration(seconds: 15));
    while (sync.servicio.enCurso && DateTime.now().isBefore(hasta)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  final avisos = avisosMpCompanion;
  avisosMpCompanion = null;
  await frenar('los avisos de Mercado Pago', () => avisos?.detener());
  await frenar('la comandera', soltarComandera);
  await frenar('la escucha de la PC', () {
    escuchaPcCompanion?.detener();
    escuchaPcCompanion = null;
  });
  await frenar('la base', () => cerrarBaseLocalCompanion(bloquear: true));
  // El bot de WhatsApp es de la cuenta (su sesión de WhatsApp vive en la carpeta de datos): se apaga, y se vuelve a prender
  // desde esa cuenta.
  if (!kIsWeb) {
    try {
      if (await botDelCelular.encendido()) await botDelCelular.apagar();
    } catch (_) {
      // Sin el servicio del bot (otra edición de la app, o un test) no hay nada que apagar.
    }
  }
}

/// Borra la cuenta activa. Si hay otras guardadas, deja anotado traer [traer] (si está guardada; si no, la última usada) al
/// abrir de nuevo y la devuelve; sin otras, el celular queda como recién instalado y devuelve null. Después hay que cerrar la
/// app de cero (`volverAEmpezar`).
Future<CuentaDelCelular?> borrarTodoDelCelular([CarpetasDelCelular? carpetas, String? traer]) async {
  await frenarLoQueEscribe();

  if (kIsWeb) {
    // En el navegador (Nodo Sur Servicios web) no hay carpetas: la base vive en el almacenamiento del navegador y la cuenta en
    // las preferencias. Importa más que en un celular: puede ser una compu compartida.
    await borrarBaseDelNavegador(nombreBaseCelular);
    await (await SharedPreferences.getInstance()).clear();
    return null;
  }
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  await descartarActiva(c);
  final otra = await traerOtraTrasBorrar(c, traer);
  // Sin otras cuentas, como antes: también se van las preferencias del aparato (tema), como recién instalado.
  if (otra == null) await (await SharedPreferences.getInstance()).clear();
  return otra;
}

/// Cierra la app del todo. Solo cuando la persona lo pide (la pantalla de un cambio trabado): cambiar de negocio ya no cierra
/// la app (`volverAEmpezar`).
Future<void> cerrarLaApp() async {
  await SystemNavigator.pop();
  exit(0);
}

