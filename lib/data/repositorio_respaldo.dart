// Respaldo y restauración de la base (fase 10, prioridad 1-2).
//
// `VACUUM INTO` en vez de copiar el archivo a mano: es una sola sentencia
// atómica que SQLite garantiza consistente aunque la base esté abierta y en
// uso — copiar el archivo con `File.copy` mientras la app lo tiene abierto
// podría capturar un estado a medio escribir.
//
// La lista de respaldos disponibles se arma leyendo la carpeta configurada,
// no llevando un registro aparte en la base: así nunca se puede desincronizar
// de lo que realmente hay en el disco.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/respaldo.dart';
import 'database.dart';

class ArchivoRespaldo {
  final String ruta;
  final String nombre;
  final DateTime fecha;
  final int tamanioBytes;

  const ArchivoRespaldo({
    required this.ruta,
    required this.nombre,
    required this.fecha,
    required this.tamanioBytes,
  });
}

final RegExp _patronNombre = RegExp(r'^la_plazoleta_(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})(\d{2})\.sqlite$');

DateTime? _fechaDesdeNombre(String nombre) {
  final match = _patronNombre.firstMatch(nombre);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

Future<String?> carpetaRespaldo(AppDatabase db) async {
  final config = await db.select(db.configuracionTabla).getSingle();
  return config.rutaRespaldoCarpeta;
}

Future<void> configurarCarpetaRespaldo(AppDatabase db, String? ruta) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(rutaRespaldoCarpeta: Value(ruta)));
}

Future<int> cantidadCopiasConfigurada(AppDatabase db) async {
  final config = await db.select(db.configuracionTabla).getSingle();
  return config.respaldoCantidadCopias;
}

Future<void> configurarCantidadCopias(AppDatabase db, int cantidad) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(respaldoCantidadCopias: Value(cantidad)));
}

/// Respaldos existentes en la carpeta configurada, ordenados de más viejo a
/// más nuevo según la fecha embebida en el nombre (no la fecha de
/// modificación del archivo, que un sincronizador como Drive/OneDrive podría
/// alterar). Ignora cualquier archivo que no matchee el patrón esperado.
Future<List<ArchivoRespaldo>> listarRespaldos(AppDatabase db) async {
  final carpeta = await carpetaRespaldo(db);
  if (carpeta == null) return [];
  final dir = Directory(carpeta);
  if (!await dir.exists()) return [];

  final resultado = <ArchivoRespaldo>[];
  await for (final entidad in dir.list()) {
    if (entidad is! File) continue;
    final nombre = p.basename(entidad.path);
    final fecha = _fechaDesdeNombre(nombre);
    if (fecha == null) continue;
    resultado.add(ArchivoRespaldo(
      ruta: entidad.path,
      nombre: nombre,
      fecha: fecha,
      tamanioBytes: await entidad.length(),
    ));
  }
  resultado.sort((a, b) => a.fecha.compareTo(b.fecha));
  return resultado;
}

/// Hace un respaldo nuevo y rota los más viejos si se supera la cantidad
/// configurada. Tira `StateError` si no hay carpeta configurada — nunca
/// escribe en un lugar que el dueño no eligió.
Future<String> hacerRespaldo(AppDatabase db) async {
  final carpeta = await carpetaRespaldo(db);
  if (carpeta == null) {
    throw StateError('No hay carpeta de respaldo configurada');
  }
  await Directory(carpeta).create(recursive: true);

  final destino = p.join(carpeta, nombreArchivoRespaldo(DateTime.now()));
  await db.customStatement('VACUUM INTO ?', [destino]);

  final cantidad = await cantidadCopiasConfigurada(db);
  final existentes = await listarRespaldos(db);
  final aEliminar = nombresAEliminar(
    nombresOrdenadosDeViejoANuevo: existentes.map((a) => a.nombre).toList(),
    maximoCopias: cantidad,
  );
  for (final nombre in aEliminar) {
    final archivo = File(p.join(carpeta, nombre));
    if (await archivo.exists()) await archivo.delete();
  }

  return destino;
}

/// La ruta real del archivo de la base, replicando cómo `drift_flutter`
/// la resuelve por default (`$name.sqlite` en `getApplicationDocumentsDirectory()`)
/// — hace falta conocerla aparte para poder restaurar sobre ella.
Future<String> rutaArchivoBaseDeDatos() async {
  final directorio = await getApplicationDocumentsDirectory();
  return p.join(directorio.path, 'la_plazoleta.sqlite');
}

/// Copia [rutaRespaldo] sobre [rutaDestino]. El llamador es responsable de
/// haber cerrado la conexión activa a la base ANTES de llamar a esto (no se
/// puede sobrescribir un archivo que SQLite todavía tiene abierto) y de
/// reiniciar la app después — ver `PantallaRespaldo`, que hace las tres cosas
/// en orden.
///
/// Reemplazo a prueba de cortes (revisión 2026-10-04): antes era un `File.copy` directo encima de la base, así que un corte de
/// luz a mitad de la copia dejaba la base real a medias y sin respaldo del estado anterior. Ahora:
///  1. se copia al lado, a `<destino>.restaurando`, y se comprueba que pesa lo mismo que el original;
///  2. la base que se va a reemplazar queda guardada como `<destino>.antes-de-restaurar` (una sola copia, la última): restaurar
///     el archivo equivocado ya no es irreversible;
///  3. se borran los `-wal` / `-shm` / `-journal` de la base vieja (aplicados a la nueva la corromperían);
///  4. se renombra el temporal sobre el destino (el renombrado es atómico en el mismo disco): o queda la base vieja entera o la
///     nueva entera, nunca una mezcla.
Future<void> restaurarDesdeArchivo({required String rutaRespaldo, required String rutaDestino}) async {
  final origen = File(rutaRespaldo);
  final destino = File(rutaDestino);
  final temporal = File('$rutaDestino.restaurando');
  try {
    await origen.copy(temporal.path);
    if (await temporal.length() != await origen.length()) {
      throw const FileSystemException('La copia del respaldo quedó incompleta');
    }
    if (await destino.exists()) await destino.copy('$rutaDestino.antes-de-restaurar');
    for (final sufijo in const ['-wal', '-shm', '-journal']) {
      final resto = File('$rutaDestino$sufijo');
      if (await resto.exists()) await resto.delete();
    }
    await temporal.rename(rutaDestino);
  } catch (_) {
    // Cualquier falla deja la base actual como estaba y sin restos a medias.
    if (await temporal.exists()) await temporal.delete();
    rethrow;
  }
}

/// Relanza el mismo ejecutable y termina el proceso actual — la forma más
/// simple y robusta de que la app "abra limpia" después de restaurar, en vez
/// de tratar de recargar en memoria todo el estado de una app ya corriendo.
/// Función aparte (no inline en la pantalla) para poder inyectar un stub en
/// los tests de widget, que no pueden ejecutar esto de verdad sin matar el
/// proceso de test.
void reiniciarAppComoNueva() {
  Process.start(Platform.resolvedExecutable, []);
  exit(0);
}
