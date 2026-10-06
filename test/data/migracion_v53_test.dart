// Prueba de upgrade REAL (v52 → v53: WhatsApp del proveedor) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v52 real sube a v53: los proveedores quedan igual, sin WhatsApp, y se puede guardar uno', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v53_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE proveedores DROP COLUMN whatsapp');
      crudo.execute('PRAGMA user_version = 52');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final serra = (await db.select(db.proveedores).get()).firstWhere((p) => p.codigo == 'SE');
    expect(serra.nombre, 'Serra');
    expect(serra.whatsapp, isNull);

    await (db.update(db.proveedores)..where((p) => p.id.equals(serra.id))).write(const ProveedoresCompanion(whatsapp: Value('294 4123456')));
    expect((await db.select(db.proveedores).get()).firstWhere((p) => p.codigo == 'SE').whatsapp, '294 4123456');
  });
}
