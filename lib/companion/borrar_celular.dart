// "Cerrar sesión y borrar este celular" (El dueño, 2026-10-10: "no se puede cerrar sesión y eliminar los datos de la
// aplicación sin tener que borrarlos desde configuraciones" de Android). Deja el celular como recién instalado: la base
// local, la cuenta vinculada, el estado de la sync, el perfil, el modo de uso, la PC emparejada y las preferencias.
//
// Lo que ya subió a la nube (o está en la PC) no se toca: entrando de nuevo con la misma cuenta vuelve a bajar. Lo que
// no subió todavía se pierde, y la pantalla lo avisa antes.
//
// Después de borrar, la app se cierra: varias piezas viven en memoria mientras la app está abierta (la base abierta, la
// sync, la escucha de la PC, la clave de la IA). Cerrar y volver a abrir arranca todo de cero sin depender de acordarse
// de cada una.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'base_local.dart';
import 'escucha_pc.dart';
import 'sync_nube_companion.dart';

/// Nombre de la base del celular (`AppDatabase._abrirConexion`, `driftDatabase(name: 'la_plazoleta')`).
const _nombreBase = 'la_plazoleta';

Future<void> borrarTodoDelCelular() async {
  // Primero se frena todo lo que escribe: si la sync baja algo mientras se borra, la base vuelve a aparecer a medias.
  syncNubeCompanion?.servicio.detener();
  escuchaPcCompanion?.detener();
  escuchaPcCompanion = null;
  await cerrarBaseLocalCompanion();

  final documentos = await getApplicationDocumentsDirectory();
  for (final sufijo in ['', '-wal', '-shm', '-journal']) {
    await _borrar(File(p.join(documentos.path, '$_nombreBase.sqlite$sufijo')));
  }
  // La cuenta vinculada, el estado de la sync, el bot y los registros viven acá.
  final soporte = await getApplicationSupportDirectory();
  if (await soporte.exists()) {
    await for (final e in soporte.list()) {
      await _borrar(e);
    }
  }
  // Perfil, modo de uso, PC emparejada, id del equipo y el resto de las preferencias.
  await (await SharedPreferences.getInstance()).clear();
}

Future<void> _borrar(FileSystemEntity e) async {
  try {
    if (await e.exists()) await e.delete(recursive: true);
  } on FileSystemException {
    // Un archivo que no se deja borrar no frena el resto: lo importante (cuenta, preferencias) igual se borra.
  }
}
