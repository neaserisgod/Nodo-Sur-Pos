// Prueba de upgrade REAL (v66 → v67: la base de stock de cada producto, El dueño 2026-10-13: "el stock subió y yo no lo
// subí") contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v66 real sube a v67: aparece la tabla de bases vacía y el stock no se toca', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v67_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE bases_de_stock');
      crudo.execute(
        "INSERT INTO productos (nombre, precio_centavos, costo_centavos, stock, global_id, origen_dispositivo) "
        "VALUES ('Yerba Playadito 1 kg', 520000, 380000, 12, 'yerba-gid', 'desktop')",
      );
      crudo.execute('PRAGMA user_version = 66');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final yerba = await (db.select(db.productos)..where((p) => p.nombre.equals('Yerba Playadito 1 kg'))).getSingle();
    expect(yerba.stock, 12);
    expect(await db.select(db.basesDeStock).get(), isEmpty, reason: 'nace vacía');
    final indices = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'bases_de_stock'").get();
    expect(indices.map((i) => i.data['name']), contains('idx_bases_de_stock_global_id'));

    // La PC (origen de los productos de antes) la llena antes de subir: 12 sin movimientos.
    establecerIdDispositivo('desktop');
    final bases = await cambiosDesde(db, tabla: 'bases_de_stock', desde: 0);
    expect(bases.where((b) => b['global_id'] == 'yerba-gid').single['stock_base'], 12);
  });
}
