// Prueba de upgrade REAL (v44 → v45: `proveedores.caja_aparte`, fase 4 de la generalización) contra un archivo
// de verdad, mismo motivo que `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/base_para_tests.dart';

Future<File> _baseV44({required bool sinColumna}) async {
  final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v45_');
  addTearDown(() => carpeta.delete(recursive: true));
  final archivo = File('${carpeta.path}/base.sqlite');
  final nueva = AppDatabase(NativeDatabase(archivo), sembrarCatalogoDeTest);
  await nueva.select(nueva.proveedores).get();
  await nueva.close();
  final crudo = sqlite3.sqlite3.open(archivo.path);
  try {
    crudo.execute('UPDATE proveedores SET actualizado_en = 1234');
    if (sinColumna) crudo.execute('ALTER TABLE proveedores DROP COLUMN caja_aparte');
    crudo.execute('PRAGMA user_version = 44');
  } finally {
    crudo.close();
  }
  return archivo;
}

void main() {
  test('una base v44 real sube a v45: Serra Cigarros queda con caja aparte y nadie más', () async {
    final archivo = await _baseV44(sinColumna: true);
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());

    final todos = await db.select(db.proveedores).get();
    expect(todos.length, greaterThan(10));
    expect(todos.where((p) => p.cajaAparte).map((p) => p.codigo), ['SC']);
    // No se toca la fecha de modificación: nada se reenvía por sync por esta migración.
    expect(todos.every((p) => p.actualizadoEn!.millisecondsSinceEpoch == 1234 * 1000), isTrue);
  });

  test('una base v44 sin Serra Cigarros sube igual y nadie queda con caja aparte', () async {
    final archivo = await _baseV44(sinColumna: true);
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute("DELETE FROM proveedores WHERE codigo = 'SC'");
    } finally {
      crudo.close();
    }
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect((await db.select(db.proveedores).get()).where((p) => p.cajaAparte), isEmpty);
  });

  test('subir con la columna ya presente no falla', () async {
    final archivo = await _baseV44(sinColumna: false);
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect((await (db.select(db.proveedores)..where((p) => p.codigo.equals('SC'))).getSingle()).cajaAparte, isTrue);
  });

  test('una base nueva de verdad no trae ningún proveedor con caja aparte', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    expect(await db.select(db.proveedores).get(), isEmpty);
  });
}
