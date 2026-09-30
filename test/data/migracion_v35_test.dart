// Prueba de upgrade REAL (v34 → v35, parte de lo separado que está en
// Mercado Pago — El dueño, 2026-09-26) contra un archivo de verdad, mismo
// motivo que `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/base_para_tests.dart';

void main() {
  test('una base v34 real sube a v35: lo ya separado queda entero del cajón (parte MP en 0)', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v35_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');

    var db = AppDatabase(NativeDatabase(archivo), sembrarCatalogoDeTest);
    await db.customStatement("UPDATE proveedores SET separado_centavos = 90000 WHERE codigo = 'S'");
    await db.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE proveedores DROP COLUMN separado_mp_centavos');
      crudo.execute('PRAGMA user_version = 34');
    } finally {
      crudo.close();
    }

    db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final serra = await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle();
    expect(serra.separadoCentavos, 90000);
    expect(serra.separadoMpCentavos, 0);
  });
}
