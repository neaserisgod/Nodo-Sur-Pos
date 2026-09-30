import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/importar_base.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late List<int> baseCruda;

  setUp(() async {
    db = baseDeTest();
    tmp = await Directory.systemTemp.createTemp('importar_base_');
    baseCruda = gzip.decode((await armarCopia(db, carpetaTemporal: tmp)).bytes);
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<String> escribir(String nombre, List<int> bytes) async {
    final f = File('${tmp.path}/$nombre')..writeAsBytesSync(bytes);
    return f.path;
  }

  Future<BaseParaImportar> preparar(String ruta) => prepararImportacion(ruta, esquemaActual: db.schemaVersion, carpetaTemporal: Directory('${tmp.path}/listas'));

  Future<void> rechaza(String ruta, String contiene) => expectLater(
    preparar(ruta),
    throwsA(isA<ErrorImportacion>().having((e) => e.mensaje, 'mensaje', contains(contiene))),
  );

  test('un .sqlite de la versión actual se acepta y queda listo para abrir', () async {
    final r = await preparar(await escribir('mi_base.sqlite', baseCruda));
    expect(r.schemaVersion, db.schemaVersion);
    expect(r.vieja, isFalse);
    final otra = AppDatabase(NativeDatabase(File(r.ruta)));
    addTearDown(otra.close);
    expect((await otra.select(otra.usuarios).get()).single.nombre, 'Dueño');
  });

  test('también se acepta comprimido (.gz), como lo entrega la cuenta', () async {
    final r = await preparar(await escribir('copia.sqlite.gz', gzip.encode(baseCruda)));
    expect(r.schemaVersion, db.schemaVersion);
    expect(File(r.ruta).readAsBytesSync().sublist(0, 15), baseCruda.sublist(0, 15));
  });

  test('una base de una versión anterior se acepta y se marca como vieja (la app la actualiza al abrirla)', () async {
    final vieja = List<int>.from(baseCruda)..[63] = 40; // user_version = 40
    final r = await preparar(await escribir('vieja.sqlite', vieja));
    expect(r.schemaVersion, 40);
    expect(r.vieja, isTrue);
  });

  test('una base de una versión MÁS NUEVA se rechaza con un aviso claro', () async {
    final nueva = List<int>.from(baseCruda)..[63] = db.schemaVersion + 1;
    await rechaza(await escribir('nueva.sqlite', nueva), 'más nueva');
  });

  test('una base demasiado vieja (anterior a las migraciones probadas) se rechaza', () async {
    final muyVieja = List<int>.from(baseCruda)..[63] = 3;
    await rechaza(await escribir('muy_vieja.sqlite', muyVieja), 'demasiado vieja');
  });

  test('un archivo que no es SQLite, vacío, inexistente o un .gz roto se rechaza', () async {
    await rechaza(await escribir('foto.png', List.filled(500, 9)), 'no es una base');
    await rechaza(await escribir('vacio.sqlite', []), 'vacío');
    await rechaza('${tmp.path}/no_existe.sqlite', 'No se encontró');
    await rechaza(await escribir('roto.gz', [0x1f, 0x8b, 1, 2, 3, 4, 5]), 'comprimido');
  });

  test('una SQLite de otro programa (sin las tablas del sistema) se rechaza', () async {
    final ajena = List<int>.from(baseCruda);
    // Cambia el nombre de la tabla clave por otro de igual largo: sigue siendo SQLite, pero no de este sistema.
    final texto = String.fromCharCodes(ajena);
    final i = texto.indexOf('sesiones_de_caja');
    for (var k = 0; k < 16; k++) {
      ajena[i + k] = 'x'.codeUnitAt(0);
    }
    // Todas las apariciones (tabla, índices).
    var desde = 0;
    while (true) {
      final j = String.fromCharCodes(ajena).indexOf('sesiones_de_caja', desde);
      if (j < 0) break;
      for (var k = 0; k < 16; k++) {
        ajena[j + k] = 'x'.codeUnitAt(0);
      }
      desde = j + 16;
    }
    await rechaza(await escribir('ajena.sqlite', ajena), 'no parece');
  });

  test('no toca la base en uso ni deja nada suelto si se rechaza', () async {
    await rechaza(await escribir('foto.png', List.filled(500, 9)), 'no es una base');
    expect(Directory('${tmp.path}/listas').existsSync(), isFalse);
    expect((await db.select(db.usuarios).get()).length, 1);
  });
}
