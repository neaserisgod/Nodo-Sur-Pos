// Prueba de upgrade REAL (v51 → v52: facturas de compra con IA) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`:
// lo que se rompe en una base vieja no se ve en una base nueva de test.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v51 real sube a v52: aparecen las tablas de vínculos y CUIT y no se pierde lo que había', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v52_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final proveedorId = await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
    await nueva.into(nueva.productos).insert(ProductosCompanion.insert(nombre: 'Alfajor', proveedorId: Value(proveedorId)));
    await nueva.close();

    // Como estaba antes de esta versión: sin las dos tablas nuevas.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE vinculos_factura');
      crudo.execute('DROP TABLE cuits_proveedor');
      crudo.execute('PRAGMA user_version = 51');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final tablas = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.data['name']);
    expect(tablas, containsAll(['vinculos_factura', 'cuits_proveedor']));
    expect((await db.select(db.productos).get()).map((p) => p.nombre), contains('Alfajor'), reason: 'el catálogo sigue ahí');

    // Y se pueden usar de una.
    final proveedor = (await db.select(db.proveedores).get()).firstWhere((p) => p.codigo == 'SE');
    await asociarCuit(db, proveedorId: proveedor.id, cuit: '30670378213');
    expect((await proveedorPorCuit(db, '30670378213'))!.id, proveedor.id);
  });
}
