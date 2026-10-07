// Prueba de upgrade REAL (v59 → v60: umbral de faltantes del cierre configurable) contra un archivo de verdad, mismo
// motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/faltantes_cierre.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v59 real sube a v60: la configuración queda igual y el umbral arranca en el valor de entrada', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v60_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.update(nueva.configuracionTabla).write(const ConfiguracionTablaCompanion(fondoFijoCentavos: Value(4200000)));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE configuracion_tabla DROP COLUMN umbral_faltante_centavos');
      crudo.execute('PRAGMA user_version = 59');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final config = await db.select(db.configuracionTabla).getSingle();
    expect(config.fondoFijoCentavos, 4200000);
    expect(config.umbralFaltanteCentavos, umbralFaltantePorDefectoCentavos);
  });
}
