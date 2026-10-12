import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import '../../data/database.dart';

/// El mismo `sqlite3.wasm` que la base de siempre, pero sin el worker ni OPFS: nada queda guardado en el navegador.
/// Se pide contra la base de la página (/app/), no contra la dirección: la demo se abre en /demo/, donde no hay archivos.
Future<AppDatabase> abrirBaseDemo() async {
  final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse(web.document.baseURI).resolve('sqlite3.wasm'));
  // SQLite en WebAssembly no trae ningún sistema de archivos: sin uno en memoria, ni siquiera abre una base en memoria.
  sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return AppDatabase(WasmDatabase.inMemory(sqlite3));
}
