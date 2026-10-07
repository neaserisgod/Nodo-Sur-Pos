// Prueba de upgrade REAL (v55 → v56: un CUIT para varios proveedores) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v55 real sube a v56: el CUIT cargado sigue y se le puede sumar un segundo proveedor', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v56_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final x = await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'X', nombre: 'X'));
    final xCig = await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'XC', nombre: 'X cigarrillos'));
    await nueva.close();

    // Como estaba en la v55: el CUIT era único en toda la tabla.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE cuits_proveedor');
      crudo.execute(
        'CREATE TABLE cuits_proveedor (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'proveedor_id INTEGER NOT NULL REFERENCES proveedores (id), cuit TEXT NOT NULL UNIQUE)',
      );
      crudo.execute("INSERT INTO cuits_proveedor (proveedor_id, cuit) VALUES ($x, '30670378213')");
      crudo.execute('PRAGMA user_version = 55');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect((await proveedoresPorCuit(db, '30670378213')).map((p) => p.id), [x], reason: 'lo que ya había aprendido sigue');

    await asociarCuit(db, proveedorId: xCig, cuit: '30670378213');
    expect((await proveedoresPorCuit(db, '30670378213')).map((p) => p.id), [x, xCig]);
  });
}
