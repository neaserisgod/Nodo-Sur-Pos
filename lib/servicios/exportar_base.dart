// Exportar la base del celular (El dueño, 2026-10-16: "poder exportar la base de datos de la aplicación de almacén"). Es la
// misma copia que va a la cuenta (`armarCopia`: consistente aunque la base esté abierta, sin tokens y comprimida) en un archivo
// con fecha, para mandarla por WhatsApp, Drive o mail. La PC la importa tal cual (Configuración › Respaldo › Importar).

import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'copias_nube.dart' show armarCopia;

String _dos(int n) => n.toString().padLeft(2, '0');

/// "NodoSur-base-2026-10-16-1530.sqlite.gz".
String nombreArchivoExportado(DateTime momento) =>
    'NodoSur-base-${momento.year}-${_dos(momento.month)}-${_dos(momento.day)}-${_dos(momento.hour)}${_dos(momento.minute)}.sqlite.gz';

/// Arma el archivo en [carpeta] y devuelve su ruta.
Future<String> exportarBase(AppDatabase db, {required Directory carpeta, DateTime? ahora}) async {
  final copia = await armarCopia(db, carpetaTemporal: carpeta);
  final archivo = File(p.join(carpeta.path, nombreArchivoExportado(ahora ?? DateTime.now())));
  await archivo.writeAsBytes(copia.bytes, flush: true);
  return archivo.path;
}
