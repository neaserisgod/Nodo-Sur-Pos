// Importar una base desde un archivo: para cuando solo quedó el `.sqlite` (la PC se rompió, o se pasa la base a otra).
// Acepta el archivo tal cual, o comprimido (`.gz`, como lo entrega la cuenta de Nodo Sur). Acá solo se valida y se deja
// el archivo listo; reemplazar la base y reiniciar lo hace el mismo camino que restaurar un respaldo.
//
// Una base de una versión anterior se acepta: la app la actualiza sola al abrirla. Una de una versión MÁS NUEVA no, porque
// esta app no sabe leerla.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/respaldo.dart';

/// Las migraciones cubren bases desde esta versión (las anteriores no se probaron nunca).
const int esquemaMinimoImportable = 10;

/// Una base lista para reemplazar a la actual.
class BaseParaImportar {
  const BaseParaImportar({required this.ruta, required this.schemaVersion, required this.vieja, required this.tamanioBytes});

  /// Archivo SQLite ya sin comprimir, en la carpeta temporal.
  final String ruta;
  final int schemaVersion;

  /// De una versión anterior a la de la app: se va a actualizar al abrirla.
  final bool vieja;
  final int tamanioBytes;
}

class ErrorImportacion implements Exception {
  const ErrorImportacion(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Comprueba que [rutaArchivo] sea una base de este sistema que la app pueda abrir, y la deja lista en [carpetaTemporal].
/// Tira [ErrorImportacion] con un texto para mostrar; nunca toca la base en uso.
Future<BaseParaImportar> prepararImportacion(
  String rutaArchivo, {
  required int esquemaActual,
  required Directory carpetaTemporal,
}) async {
  final archivo = File(rutaArchivo);
  if (!await archivo.exists()) throw const ErrorImportacion('No se encontró el archivo.');
  List<int> bytes = await archivo.readAsBytes();
  if (bytes.isEmpty) throw const ErrorImportacion('El archivo está vacío.');

  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    try {
      bytes = gzip.decode(bytes);
    } catch (_) {
      throw const ErrorImportacion('No se pudo abrir el archivo comprimido.');
    }
  }

  final version = versionDeEsquemaDeArchivo(bytes);
  if (version == null) throw const ErrorImportacion('Ese archivo no es una base de datos SQLite.');
  // Toda base de este sistema tiene la tabla de sesiones de caja; una SQLite cualquiera no.
  if (!latin1.decode(bytes, allowInvalid: true).contains('sesiones_de_caja')) {
    throw const ErrorImportacion('Ese archivo no parece ser una base de este sistema.');
  }
  if (version > esquemaActual) {
    throw const ErrorImportacion('Esa base es de una versión más nueva de la app. Actualizá la app y volvé a probar.');
  }
  if (version < esquemaMinimoImportable) {
    throw ErrorImportacion('Esa base es demasiado vieja (versión $version) para importarla.');
  }

  await carpetaTemporal.create(recursive: true);
  final destino = File(p.join(carpetaTemporal.path, 'importar_${DateTime.now().microsecondsSinceEpoch}.sqlite'));
  await destino.writeAsBytes(bytes, flush: true);
  return BaseParaImportar(ruta: destino.path, schemaVersion: version, vieja: version < esquemaActual, tamanioBytes: bytes.length);
}
