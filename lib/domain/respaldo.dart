import 'dart:typed_data';

// Respaldo de la base de datos (fase 10). El mecanismo real de copia
// (VACUUM INTO) vive en la capa de datos — acá solo la parte pura: el nombre
// determinístico de cada copia y qué copias sobran al rotar.

/// Nombre de archivo para un respaldo tomado en [momento] — incluye fecha y
/// hora hasta el segundo, así dos respaldos nunca chocan de nombre salvo que
/// ocurran en el mismo instante exacto (Regla explícita: rotar, nunca pisar).
String nombreArchivoRespaldo(DateTime momento) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return 'la_plazoleta_${momento.year}-${dos(momento.month)}-${dos(momento.day)}_'
      '${dos(momento.hour)}${dos(momento.minute)}${dos(momento.second)}.sqlite';
}

/// De una lista de nombres ya ordenada de más viejo a más nuevo, cuáles hay
/// que borrar para no superar [maximoCopias]. Siempre los más viejos primero.
List<String> nombresAEliminar({
  required List<String> nombresOrdenadosDeViejoANuevo,
  required int maximoCopias,
}) {
  final exceso = nombresOrdenadosDeViejoANuevo.length - maximoCopias;
  if (exceso <= 0) return const [];
  return nombresOrdenadosDeViejoANuevo.sublist(0, exceso);
}

/// `user_version` de un archivo SQLite, leído de su cabecera (bytes 60–63). Null si no es una base SQLite.
int? versionDeEsquemaDeArchivo(List<int> bytes) {
  const magia = 'SQLite format 3\u0000';
  if (bytes.length < 100) return null;
  for (var i = 0; i < magia.length; i++) {
    if (bytes[i] != magia.codeUnitAt(i)) return null;
  }
  return ByteData.sublistView(Uint8List.fromList(bytes.sublist(60, 64))).getUint32(0);
}
