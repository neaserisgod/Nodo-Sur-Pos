// Prueba de upgrade REAL (v60 → v61: la cuenta corriente y las facturas de compra se sincronizan) contra un archivo de verdad, mismo
// motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v60 real sube a v61: la deuda que ya había sigue y queda lista para sincronizar, con su fecha real', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v61_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final usuario = (await nueva.select(nueva.usuarios).get()).first.id;
    final proveedor = await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'X', nombre: 'X'));
    await nueva.close();

    // Como estaba en la v60: sin las columnas de sincronización, con un cargo de antes.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      for (final (tabla, columnas) in [
        ('movimientos_deuda', ['global_id', 'origen_dispositivo', 'actualizado_en']),
        ('facturas_compra', ['global_id', 'origen_dispositivo', 'actualizado_en']),
        ('productos_factura_compra', ['global_id', 'origen_dispositivo']),
        ('vinculos_factura', ['global_id', 'origen_dispositivo']),
        ('cuits_proveedor', ['global_id', 'origen_dispositivo']),
      ]) {
        crudo.execute('DROP INDEX IF EXISTS idx_${tabla}_global_id');
        for (final c in columnas) {
          crudo.execute('ALTER TABLE $tabla DROP COLUMN $c');
        }
      }
      crudo.execute(
        'INSERT INTO movimientos_deuda (proveedor_id, tipo, monto_centavos, fecha, usuario_id, creado_en) '
        "VALUES ($proveedor, 'CARGO', 50000, 1759800000, $usuario, 1759800000)",
      );
      crudo.execute('PRAGMA user_version = 60');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect(await saldoDeuda(db, proveedor), 50000);
    final filas = await cambiosDesde(db, tabla: 'movimientos_deuda', desde: 0);
    expect(filas, hasLength(1));
    expect(filas.single['global_id'], isNotNull);
    expect(filas.single['actualizado_en'], 1759800000, reason: 'la fecha real del cargo, no la de hoy');
  });
}
