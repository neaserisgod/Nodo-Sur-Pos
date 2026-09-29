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
