// Dónde vive el archivo de la base (`la_plazoleta.sqlite`). En Android y en la PC del almacén, en la carpeta de documentos,
// como siempre. En Nodo Sur Servicios de Windows NO: ahí documentos es la carpeta "Documentos" del usuario, la misma donde la
// app de almacén guarda su base, y las dos apps conviven en la misma compu (El dueño, 2026-10-15). Va dentro de su propia
// carpeta de datos (que es distinta porque el nombre del producto es otro), en `base/`.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../edicion.dart';

/// La subcarpeta de la carpeta de datos donde Nodo Sur Servicios de Windows guarda su base.
const subcarpetaBaseEscritorio = 'base';

Future<Directory> carpetaDeLaBase() async {
  if (!esEscritorioServicios) return getApplicationDocumentsDirectory();
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, subcarpetaBaseEscritorio));
  await dir.create(recursive: true);
  return dir;
}
