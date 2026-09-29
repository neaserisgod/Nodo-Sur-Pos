// Prueba de upgrade REAL (v37 → v38: separación del día por proveedor, para
// poder destildar en Separaciones — Bruno, 2026-09-26) contra un archivo de
// verdad, mismo motivo que `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v37 real sube a v38: los proveedores quedan sin separación del día', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v38_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');

    var db = AppDatabase(NativeDatabase(archivo));
    await db.customStatement("UPDATE proveedores SET separado_centavos = 90000 WHERE codigo = 'S'");
    await db.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      for (final c in [
        'separado_del_dia_fecha',
        'separado_del_dia_centavos',
        'separado_del_dia_mp_centavos',
        'corte_antes_del_dia',
        'pendiente_base_antes_del_dia_centavos',
      ]) {
        crudo.execute('ALTER TABLE proveedores DROP COLUMN $c');
      }
      crudo.execute('PRAGMA user_version = 37');
    } finally {
      crudo.close();
    }

    db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final serra = await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle();
    expect(serra.separadoCentavos, 90000);
    expect(serra.separadoDelDiaFecha, isNull);
    expect(serra.separadoDelDiaCentavos, 0);
    expect(serra.pendienteBaseAntesDelDiaCentavos, 0);
  });
}
