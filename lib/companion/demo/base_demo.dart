// La base de la demo, en memoria (`demo.dart`). En el navegador, SQLite en WebAssembly sin guardar nada; fuera (tests), la nativa.
export 'base_demo_io.dart' if (dart.library.js_interop) 'base_demo_web.dart';
