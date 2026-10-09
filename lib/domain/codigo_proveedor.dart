// Código de un proveedor nuevo cargado desde el celular (El dueño, 2026-10-09: "no deben quedar datos importantes sin
// poder llenar, por ej. un proveedor"). El código es único en la base y la PC lo pide en el alta, pero para quien carga
// desde el celular es un dato técnico: se arma solo con las iniciales del nombre y se puede cambiar después en la PC.

const _acentos = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N'};

/// Las iniciales de [nombre] (hasta tres, en mayúsculas y sin acentos). Si ya está en [existentes] (sin distinguir
/// mayúsculas) le suma un número: "CC" → "CC2" → "CC3". Un nombre sin letras ni números usa "P".
String codigoProveedorNuevo(String nombre, Iterable<String> existentes) {
  final limpio = nombre.toUpperCase().split('').map((c) => _acentos[c] ?? c).join();
  final palabras = limpio.split(RegExp(r'[^A-Z0-9]+')).where((p) => p.isNotEmpty);
  var base = palabras.take(3).map((p) => p[0]).join();
  if (base.isEmpty) base = 'P';

  final usados = {for (final c in existentes) c.toUpperCase()};
  if (!usados.contains(base)) return base;
  for (var n = 2; ; n++) {
    final candidato = '$base$n';
    if (!usados.contains(candidato)) return candidato;
  }
}
