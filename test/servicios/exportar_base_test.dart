// Exportar la base del celular: el archivo lleva fecha, no deja tokens y la PC lo importa tal cual.
import 'dart:io';

import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/importar_base.dart';
import 'package:la_plazoleta/servicios/exportar_base.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = baseDeTest();
    tmp = await Directory.systemTemp.createTemp('nodosur_exportar_');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('el nombre lleva fecha y hora', () {
    expect(nombreArchivoExportado(DateTime(2026, 10, 16, 9, 5)), 'NodoSur-base-2026-10-16-0905.sqlite.gz');
  });

  test('la PC lo importa y no lleva el token de Mercado Pago', () async {
    await db.customStatement("UPDATE configuracion_tabla SET mp_access_token = 'APP_USR-secreto-mp-123456'");
    final ruta = await exportarBase(db, carpeta: tmp, ahora: DateTime(2026, 10, 16, 9, 5));
    expect(ruta, endsWith('NodoSur-base-2026-10-16-0905.sqlite.gz'));

    final lista = await prepararImportacion(ruta, esquemaActual: db.schemaVersion, carpetaTemporal: Directory('${tmp.path}/importar'));
    final otra = AppDatabase(NativeDatabase(File(lista.ruta)));
    addTearDown(otra.close);
    final config = await otra.select(otra.configuracionTabla).get();
    expect(config.every((c) => c.mpAccessToken == null), isTrue);
  });
}
