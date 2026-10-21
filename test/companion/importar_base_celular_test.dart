// Importar una base en el celular (El dueño, 2026-10-21): se valida el archivo como en la PC, y al reemplazar se frena todo lo
// que escribe ANTES de tocar el archivo, el registro de la sync se olvida solo si la base cambió, y la app se arma de nuevo
// pase lo que pase.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/importar_base_celular.dart';
import 'package:la_plazoleta/data/importar_base.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('importar_celular_');
    usarBaseLocalDeTest(baseDeTest());
  });

  tearDown(() async {
    await cerrarBaseLocalCompanion();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base de este sistema, de la versión [version], en un archivo.
  String baseEnArchivo(String nombre, {required int version}) {
    final ruta = p.join(tmp.path, nombre);
    final db = sqlite3.open(ruta);
    db.execute('CREATE TABLE sesiones_de_caja (id INTEGER PRIMARY KEY)');
    db.execute('PRAGMA user_version = $version');
    db.close();
    return ruta;
  }

  group('prepararBaseParaElCelular', () {
    test('acepta una base de esta versión y la deja en la carpeta temporal', () async {
      final version = baseLocalCompanion().schemaVersion;
      final lista = await prepararBaseParaElCelular(baseEnArchivo('buena.sqlite', version: version), carpetaTemporal: Directory(p.join(tmp.path, 't')));
      expect(lista.schemaVersion, version);
      expect(lista.vieja, isFalse);
      expect(File(lista.ruta).existsSync(), isTrue);
    });

    test('rechaza una base de una versión más nueva que la app', () async {
      final ruta = baseEnArchivo('nueva.sqlite', version: baseLocalCompanion().schemaVersion + 1);
      expect(
        () => prepararBaseParaElCelular(ruta, carpetaTemporal: tmp),
        throwsA(isA<ErrorImportacion>().having((e) => e.mensaje, 'mensaje', contains('más nueva'))),
      );
    });

    test('rechaza un archivo que no es una base', () async {
      final ruta = p.join(tmp.path, 'foto.jpg');
      await File(ruta).writeAsString('no soy una base');
      expect(() => prepararBaseParaElCelular(ruta, carpetaTemporal: tmp), throwsA(isA<ErrorImportacion>()));
    });
  });

  group('reemplazarBaseDelCelular', () {
    test('frena, cambia el archivo, olvida la sync y arma la app, en ese orden', () async {
      final pasos = <String>[];
      final destino = p.join(tmp.path, 'la_plazoleta.sqlite');
      await File(destino).writeAsString('base vieja');
      final nueva = p.join(tmp.path, 'importada.sqlite');
      await File(nueva).writeAsString('base nueva');

      final error = await reemplazarBaseDelCelular(
        nueva,
        frenar: () async => pasos.add('frenar'),
        rutaDestino: () async => destino,
        copiar: ({required rutaRespaldo, required rutaDestino}) async {
          // La base tiene que estar ya frenada cuando se toca el archivo.
          expect(pasos, ['frenar']);
          await File(rutaRespaldo).copy(rutaDestino);
          pasos.add('copiar');
        },
        olvidarRegistroSync: () async => pasos.add('olvidar'),
        armarDeNuevo: () async => pasos.add('armar'),
      );

      expect(error, isNull);
      expect(pasos, ['frenar', 'copiar', 'olvidar', 'armar']);
      expect(await File(destino).readAsString(), 'base nueva');
    });

    test('si no se pudo cambiar el archivo, no olvida la sync, arma la app igual y devuelve el error', () async {
      final pasos = <String>[];
      final error = await reemplazarBaseDelCelular(
        p.join(tmp.path, 'no-existe.sqlite'),
        frenar: () async => pasos.add('frenar'),
        rutaDestino: () async => p.join(tmp.path, 'la_plazoleta.sqlite'),
        copiar: ({required rutaRespaldo, required rutaDestino}) async => throw const FileSystemException('sin lugar'),
        olvidarRegistroSync: () async => pasos.add('olvidar'),
        armarDeNuevo: () async => pasos.add('armar'),
      );

      expect(error, isA<FileSystemException>());
      expect(pasos, ['frenar', 'armar']);
    });
  });
}
