// Importar una base en el celular y en las ediciones de escritorio (El dueño, 2026-10-21: "quiero poder exportar la base de
// datos del sistema … y en base a eso vos escribís y me lo devolvés"). Hasta acá solo la PC del almacén importaba
// (Configuración › Respaldo); Gastro y Servicios exportaban pero no tenían cómo volver a cargar una base.
//
// Validar el archivo es lo mismo que en la PC (`prepararImportacion`). Reemplazarla no: la app del celular no se cierra y
// se arma de nuevo (`volverAEmpezar`, como al cambiar de negocio), así que primero se frena todo lo que escribe (la sync,
// los avisos, el bot) y la base queda cerrada y bloqueada mientras se cambia el archivo.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/importar_base.dart';
import '../data/repositorio_respaldo.dart' show restaurarDesdeArchivo, rutaArchivoBaseDeDatos;
import '../servicios/almacenes_del_equipo.dart' show almacenEstadoSyncDelEquipo;
import '../servicios/registro_errores.dart';
import 'base_local.dart';
import 'borrar_celular.dart' show frenarLoQueEscribe;
import 'reinicio_companion.dart' show volverAEmpezar;

/// Valida [rutaArchivo] (comprimido o no) contra la versión de la base de esta app y lo deja en una carpeta temporal.
/// Tira [ErrorImportacion] con un texto para mostrar; la base en uso no se toca.
Future<BaseParaImportar> prepararBaseParaElCelular(String rutaArchivo, {Directory? carpetaTemporal}) async {
  final temporal = carpetaTemporal ?? Directory(p.join((await getTemporaryDirectory()).path, 'nodosur_importar'));
  return prepararImportacion(rutaArchivo, esquemaActual: baseLocalCompanion().schemaVersion, carpetaTemporal: temporal);
}

/// Pone la base de [rutaPreparada] en lugar de la del celular y arma la app de nuevo. Devuelve el error si no se pudo
/// reemplazar (la base anterior queda entera y la app vuelve a andar con ella), o `null` si quedó la nueva.
///
/// El registro de la sync se olvida solo si el archivo cambió: dice "esto ya lo subí / hasta acá bajé" sobre la base de
/// antes. Sin él, la próxima vuelta baja todo de nuevo (es un upsert por `global_id`, no duplica) y sube lo que la base nueva
/// tiene y la nube no.
Future<Object?> reemplazarBaseDelCelular(
  String rutaPreparada, {
  Future<void> Function() frenar = frenarLoQueEscribe,
  Future<String> Function() rutaDestino = rutaArchivoBaseDeDatos,
  Future<void> Function({required String rutaRespaldo, required String rutaDestino}) copiar = restaurarDesdeArchivo,
  Future<void> Function() olvidarRegistroSync = _olvidarRegistroSync,
  Future<void> Function() armarDeNuevo = volverAEmpezar,
}) async {
  Object? error;
  await frenar();
  try {
    await copiar(rutaRespaldo: rutaPreparada, rutaDestino: await rutaDestino());
    await olvidarRegistroSync();
  } catch (e, st) {
    await registrarError('Importar una base en el celular', e, st);
    error = e;
  }
  // Con o sin la base nueva, la app se arma de nuevo: `frenar` dejó la base bloqueada y la sync apagada.
  await armarDeNuevo();
  return error;
}

Future<void> _olvidarRegistroSync() async => (await almacenEstadoSyncDelEquipo()).borrar();
