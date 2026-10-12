import 'package:drift/wasm.dart';

/// Borra todas las copias de la base [nombre] que guardó el navegador (OPFS o IndexedDB, según lo que haya podido usar). Los
/// mismos archivos con que se abre (`AppDatabase._abrirConexion`).
Future<void> borrarBaseDelNavegador(String nombre) async {
  final sondeo = await WasmDatabase.probe(
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
    databaseName: nombre,
  );
  for (final existente in sondeo.existingDatabases) {
    if (existente.$2 == nombre) await sondeo.deleteDatabase(existente);
  }
}
