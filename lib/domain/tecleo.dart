// Lo que muestra un campo de hora o fecha mientras se teclea solo con números. Los separadores los pone la app: el
// teclado numérico de muchos Android (Samsung, entre otros) no trae ":" ni "/", y el de "fecha y hora" a veces tampoco,
// así que no había forma de escribir un horario. Lo que no es dígito se descarta (un ":" o "/" tecleado no estorba).

/// "9" → "9", "930" → "9:30", "2000" → "20:00". Corta en 4 dígitos.
String horaTecleada(String texto) {
  final d = _digitos(texto, 4);
  if (d.length <= 2) return d;
  final corte = d.length - 2;
  return '${d.substring(0, corte)}:${d.substring(corte)}';
}

/// "10" → "10", "101" → "10/1", "10102026" → "10/10/2026". Día y mes con dos dígitos; corta en 8.
String fechaTecleada(String texto) {
  final d = _digitos(texto, 8);
  if (d.length <= 2) return d;
  if (d.length <= 4) return '${d.substring(0, 2)}/${d.substring(2)}';
  return '${d.substring(0, 2)}/${d.substring(2, 4)}/${d.substring(4)}';
}

String _digitos(String texto, int maximo) {
  final d = texto.replaceAll(RegExp(r'\D'), '');
  return d.length > maximo ? d.substring(0, maximo) : d;
}
