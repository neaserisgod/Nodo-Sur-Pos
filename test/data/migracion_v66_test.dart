// Prueba de upgrade REAL (v65 → v66: cobrar servicios, `docs/PLAN-SERVICIOS.md` etapa 3) contra un archivo de verdad, mismo
// motivo que `migracion_v47_test.dart`. Una venta de antes queda igual (no es de un servicio) y la tabla nueva nace vacía, con
// su índice de sincronización.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v65 real sube a v66: las líneas de antes no son de servicio y los consumos arrancan vacíos', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v66_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE consumos_de_linea');
      crudo.execute('ALTER TABLE lineas_de_venta DROP COLUMN es_servicio');
      final usuario = crudo.select('SELECT id FROM usuarios LIMIT 1').first['id'] as int;
      crudo.execute('INSERT INTO sesiones_de_caja (usuario_abrio_id, fondo_inicial_centavos) VALUES ($usuario, 0)');
      crudo.execute(
        'INSERT INTO ventas (sesion_caja_id, usuario_id, subtotal_centavos, total_centavos) VALUES (last_insert_rowid(), $usuario, 300000, 300000)',
      );
      crudo.execute(
        'INSERT INTO lineas_de_venta (venta_id, nombre_producto_foto, cantidad, precio_unitario_centavos, costo_unitario_centavos) '
        "VALUES (last_insert_rowid(), 'Yerba 1kg', 1, 300000, 200000)",
      );
      crudo.execute('PRAGMA user_version = 65');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final linea = await db.select(db.lineasDeVenta).getSingle();
    expect(linea.nombreProductoFoto, 'Yerba 1kg');
    expect(linea.esServicio, isFalse);
    expect(await db.select(db.consumosDeLinea).get(), isEmpty);
    final indices = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'consumos_de_linea'").get())
        .map((f) => f.data['name']);
    expect(indices, containsAll(['idx_consumos_de_linea_global_id', 'idx_consumos_de_linea_linea_venta_id']));
  });
}
