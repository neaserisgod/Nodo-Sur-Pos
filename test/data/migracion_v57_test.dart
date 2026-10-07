// Prueba de upgrade REAL (v56 → v57: aplicar facturas de compra) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v56 real sube a v57: aparecen las tablas de facturas aplicadas y no se pierde lo que había', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v57_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'EL', nombre: 'Elpar'));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE productos_factura_compra');
      crudo.execute('DROP TABLE facturas_compra');
      crudo.execute('PRAGMA user_version = 56');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final tablas = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()).map((r) => r.data['name']);
    expect(tablas, containsAll(['facturas_compra', 'productos_factura_compra']));
    expect((await db.select(db.proveedores).get()).map((p) => p.nombre), contains('Elpar'));
    expect(await db.select(db.facturasCompra).get(), isEmpty);
  });
}
