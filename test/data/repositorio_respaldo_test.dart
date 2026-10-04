import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_respaldo.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late Directory carpetaTemp;

  setUp(() async {
    db = baseDeTest();
    carpetaTemp = await Directory.systemTemp.createTemp('respaldo_test_');
  });
  tearDown(() async {
    await db.close();
    await carpetaTemp.delete(recursive: true);
  });

  group('carpeta y cantidad configurables', () {
    test('sin configurar, no hay carpeta', () async {
      expect(await carpetaRespaldo(db), isNull);
    });

    test('configurarCarpetaRespaldo la deja lista para hacerRespaldo', () async {
      await configurarCarpetaRespaldo(db, carpetaTemp.path);
      expect(await carpetaRespaldo(db), carpetaTemp.path);
    });

    test('cantidad de copias por defecto es 14', () async {
      expect(await cantidadCopiasConfigurada(db), 14);
    });
  });

  group('hacerRespaldo', () {
    test('sin carpeta configurada, tira un error claro en vez de escribir en cualquier lado', () async {
      expect(() => hacerRespaldo(db), throwsStateError);
    });

    test('crea un archivo .sqlite válido (mismo esquema) en la carpeta configurada', () async {
      await configurarCarpetaRespaldo(db, carpetaTemp.path);
      final ruta = await hacerRespaldo(db);

      expect(File(ruta).existsSync(), isTrue);
      final copia = sqlite3.sqlite3.open(ruta);
      final tablas = copia.select("SELECT name FROM sqlite_master WHERE type='table' AND name='usuarios'");
      expect(tablas, isNotEmpty);
      copia.close();
    });

    test('rota: no deja más copias que las configuradas', () async {
      await configurarCarpetaRespaldo(db, carpetaTemp.path);
      await configurarCantidadCopias(db, 2);

      // Dos respaldos "viejos" simulados a mano, con nombres ya pasados.
      File('${carpetaTemp.path}/la_plazoleta_2020-01-01_000000.sqlite').writeAsStringSync('viejo1');
      File('${carpetaTemp.path}/la_plazoleta_2020-01-02_000000.sqlite').writeAsStringSync('viejo2');

      await hacerRespaldo(db); // el tercero, debería empujar al más viejo afuera

      final restantes = await listarRespaldos(db);
      expect(restantes.length, 2);
      expect(restantes.map((a) => a.nombre), isNot(contains('la_plazoleta_2020-01-01_000000.sqlite')));
    });
  });

  group('listarRespaldos', () {
    test('sin carpeta configurada, lista vacía', () async {
      expect(await listarRespaldos(db), isEmpty);
    });

    test('ordena de más viejo a más nuevo según la fecha del nombre, ignora archivos ajenos', () async {
      await configurarCarpetaRespaldo(db, carpetaTemp.path);
      File('${carpetaTemp.path}/la_plazoleta_2026-08-30_120000.sqlite').writeAsStringSync('b');
      File('${carpetaTemp.path}/la_plazoleta_2026-08-29_120000.sqlite').writeAsStringSync('a');
      File('${carpetaTemp.path}/notas.txt').writeAsStringSync('ajeno');

      final lista = await listarRespaldos(db);
      expect(lista.map((a) => a.nombre).toList(), [
        'la_plazoleta_2026-08-29_120000.sqlite',
        'la_plazoleta_2026-08-30_120000.sqlite',
      ]);
    });
  });

  group('restaurarDesdeArchivo', () {
    test('copia el respaldo elegido sobre el destino indicado', () async {
      final origen = File('${carpetaTemp.path}/respaldo.sqlite')..writeAsStringSync('contenido de respaldo');
      final destino = '${carpetaTemp.path}/destino.sqlite';

      await restaurarDesdeArchivo(rutaRespaldo: origen.path, rutaDestino: destino);

      expect(File(destino).readAsStringSync(), 'contenido de respaldo');
    });

    test('la base que se reemplaza queda guardada como .antes-de-restaurar: restaurar el archivo equivocado no es irreversible', () async {
      final origen = File('${carpetaTemp.path}/respaldo.sqlite')..writeAsStringSync('respaldo viejo');
      final destino = File('${carpetaTemp.path}/destino.sqlite')..writeAsStringSync('base actual con las ventas de hoy');

      await restaurarDesdeArchivo(rutaRespaldo: origen.path, rutaDestino: destino.path);

      expect(destino.readAsStringSync(), 'respaldo viejo');
      expect(File('${destino.path}.antes-de-restaurar').readAsStringSync(), 'base actual con las ventas de hoy');
      expect(File('${destino.path}.restaurando').existsSync(), isFalse, reason: 'sin restos del temporal');
    });

    test('borra los -wal / -shm / -journal de la base vieja: aplicados a la nueva la corromperían', () async {
      final origen = File('${carpetaTemp.path}/respaldo.sqlite')..writeAsStringSync('nuevo');
      final destino = File('${carpetaTemp.path}/destino.sqlite')..writeAsStringSync('viejo');
      for (final s in ['-wal', '-shm', '-journal']) {
        File('${destino.path}$s').writeAsStringSync('resto');
      }

      await restaurarDesdeArchivo(rutaRespaldo: origen.path, rutaDestino: destino.path);

      for (final s in ['-wal', '-shm', '-journal']) {
        expect(File('${destino.path}$s').existsSync(), isFalse, reason: s);
      }
    });

    test('si el respaldo no existe falla sin tocar la base actual ni dejar un temporal', () async {
      final destino = File('${carpetaTemp.path}/destino.sqlite')..writeAsStringSync('base actual');

      await expectLater(
        restaurarDesdeArchivo(rutaRespaldo: '${carpetaTemp.path}/no-existe.sqlite', rutaDestino: destino.path),
        throwsA(isA<FileSystemException>()),
      );

      expect(destino.readAsStringSync(), 'base actual');
      expect(File('${destino.path}.restaurando').existsSync(), isFalse);
      expect(File('${destino.path}.antes-de-restaurar').existsSync(), isFalse);
    });

    test('una segunda restauración pisa el .antes-de-restaurar anterior (queda una sola copia, la última)', () async {
      final a = File('${carpetaTemp.path}/a.sqlite')..writeAsStringSync('A');
      final b = File('${carpetaTemp.path}/b.sqlite')..writeAsStringSync('B');
      final destino = File('${carpetaTemp.path}/destino.sqlite')..writeAsStringSync('original');

      await restaurarDesdeArchivo(rutaRespaldo: a.path, rutaDestino: destino.path);
      await restaurarDesdeArchivo(rutaRespaldo: b.path, rutaDestino: destino.path);

      expect(destino.readAsStringSync(), 'B');
      expect(File('${destino.path}.antes-de-restaurar').readAsStringSync(), 'A');
    });
  });
}
