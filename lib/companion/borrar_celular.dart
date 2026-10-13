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
// Después de borrar, la app se cierra: varias piezas viven en memoria mientras la app está abierta (la base abierta, la
// sync, la escucha de la PC, la clave de la IA). Cerrar y volver a abrir arranca todo de cero sin depender de acordarse
// de cada una.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cuentas_del_celular.dart';
import 'base_local.dart';
import 'borrar_base_navegador.dart';
import 'bot_celular.dart';
import 'cuentas_del_celular.dart';
import 'escucha_pc.dart';
import 'sync_nube_companion.dart';

/// Frena todo lo que escribe en la base o en la carpeta de datos, para poder borrarlas o moverlas: si la sync baja algo
/// mientras tanto, la base vuelve a aparecer a medias.
Future<void> frenarLoQueEscribe() async {
  syncNubeCompanion?.servicio.detener();
  escuchaPcCompanion?.detener();
  escuchaPcCompanion = null;
  await cerrarBaseLocalCompanion();
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

/// Borra la cuenta activa. Devuelve la cuenta guardada que quedó activa en su lugar ([traer] si está guardada, si no la última
/// usada), o null si el celular quedó vacío.
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
  for (final sufijo in ['', '-wal', '-shm', '-journal']) {
    await _borrar(File(p.join(c.documentos.path, '$nombreBaseCelular.sqlite$sufijo')));
  }
  // La cuenta vinculada, el estado de la sync, el bot y los registros viven acá. Las otras cuentas, no.
  if (await c.soporte.exists()) {
    await for (final e in c.soporte.list()) {
      if (e.path == c.guardadas.path) continue;
      await _borrar(e);
    }
  }
  // Perfil, modo de uso, PC emparejada, id del equipo y el resto de las preferencias de la cuenta.
  final prefs = await SharedPreferences.getInstance();
  final otras = (await leerIndiceCuentas(c)).guardadas.isNotEmpty;
  if (otras) {
    for (final k in [...prefs.getKeys()]) {
      if (esPreferenciaDeLaCuenta(k)) await prefs.remove(k);
    }
  } else {
    await prefs.clear();
  }
  return traerOtraTrasBorrar(c, traer);
}

/// Cierra la app del todo, para que al abrirla arranque de cero con la cuenta que quedó en su lugar. Cerrar la pantalla no
/// alcanza: Android puede dejar vivo el proceso (por ejemplo, con el bot de WhatsApp), y con él la base, la sync y la clave
/// de la IA de la cuenta anterior en memoria.
Future<void> cerrarLaApp() async {
  await SystemNavigator.pop();
  exit(0);
}

Future<void> _borrar(FileSystemEntity e) async {
  try {
    if (await e.exists()) await e.delete(recursive: true);
  } on FileSystemException {
    // Un archivo que no se deja borrar no frena el resto: lo importante (cuenta, preferencias) igual se borra.
  }
}
