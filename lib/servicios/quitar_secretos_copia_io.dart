import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Vacía los secretos de una copia ya hecha. `secure_delete` y `VACUUM` después: sin eso el texto viejo queda en las
/// páginas libres del archivo y se podría leer igual.
void quitarSecretos(String ruta, String sentencia) {
  final base = sqlite.sqlite3.open(ruta);
  try {
    base.execute('PRAGMA secure_delete = ON');
    base.execute(sentencia);
    base.execute('VACUUM');
  } finally {
    base.close();
  }
}
