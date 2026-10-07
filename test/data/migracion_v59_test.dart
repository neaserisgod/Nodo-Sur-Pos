// Prueba de upgrade REAL (v58 → v59: día de vencimiento de los fijos) contra un archivo de verdad, mismo motivo que
// `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v58 real sube a v59: los fijos quedan como estaban, sin fecha de vencimiento', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v59_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.into(nueva.gastosFijos).insert(GastosFijosCompanion.insert(nombre: 'Alquiler'));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE gastos_fijos DROP COLUMN dia_vencimiento');
      crudo.execute('PRAGMA user_version = 58');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final fijos = await db.select(db.gastosFijos).get();
    expect(fijos.map((g) => g.nombre), contains('Alquiler'));
    expect(fijos.every((g) => g.diaVencimiento == null), isTrue);
  });
}
