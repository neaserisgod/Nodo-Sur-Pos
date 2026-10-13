// Mismo nombre = misma persona (El dueño, 2026-10-13: "hay usuarios duplicados: aparezco tres veces"). Un perfil del POS es solo
// un nombre (Regla 18); cuando dos equipos crean el mismo perfil a la vez (cada uno entrando con la cuenta antes de haber
// bajado el del otro), quedan dos filas con distinta identidad de sync. Acá se decide cuál queda y cuáles son repetidas.
//
// La elección es la misma en todos los equipos (el `global_id` menor), así cada uno llega solo al mismo resultado sin
// hablar con los demás.

import 'normalizacion_texto.dart';

/// Lo mínimo de un perfil para agruparlo.
typedef PerfilParaUnificar = ({int id, String nombre, String? globalId, bool activo});

/// Un grupo de perfiles con el mismo nombre: el que queda y los repetidos.
class GrupoDeRepetidos {
  const GrupoDeRepetidos({required this.queda, required this.repetidos, required this.activo});
  final int queda;
  final List<int> repetidos;

  /// Si alguno del grupo está activo, la persona está activa (el dueño pudo haber desactivado justo el repetido).
  final bool activo;
}

/// Los grupos con más de un perfil. El que queda: el de `global_id` menor (los que no tienen, al final); a igualdad, el de
/// id menor.
List<GrupoDeRepetidos> agruparRepetidos(Iterable<PerfilParaUnificar> perfiles) {
  final porNombre = <String, List<PerfilParaUnificar>>{};
  for (final p in perfiles) {
    final clave = normalizarTexto(p.nombre.trim());
    if (clave.isEmpty) continue;
    (porNombre[clave] ??= []).add(p);
  }
  int orden(PerfilParaUnificar a, PerfilParaUnificar b) {
    final ga = a.globalId, gb = b.globalId;
    if (ga != null && gb != null && ga != gb) return ga.compareTo(gb);
    if (ga != null && gb == null) return -1;
    if (ga == null && gb != null) return 1;
    return a.id.compareTo(b.id);
  }

  return [
    for (final grupo in porNombre.values)
      if (grupo.length > 1)
        () {
          final ordenado = [...grupo]..sort(orden);
          return GrupoDeRepetidos(
            queda: ordenado.first.id,
            repetidos: [for (final p in ordenado.skip(1)) p.id],
            activo: grupo.any((p) => p.activo),
          );
        }(),
  ];
}
