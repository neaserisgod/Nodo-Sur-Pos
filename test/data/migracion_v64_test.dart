// Prueba de upgrade REAL (v63 → v64: los gastos fijos y sus montos se sincronizan, El dueño 2026-10-09) contra un archivo de
// verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v63 real sube a v64: los fijos y sus montos siguen y quedan listos para sincronizar', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v64_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    // Como estaba en la v63: sin las columnas de sincronización, con un fijo y su monto de antes.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      for (final tabla in ['gastos_fijos', 'gastos_fijos_montos']) {
        crudo.execute('DROP INDEX IF EXISTS idx_${tabla}_global_id');
        for (final c in ['global_id', 'origen_dispositivo', 'actualizado_en']) {
          crudo.execute('ALTER TABLE $tabla DROP COLUMN $c');
        }
      }
      crudo.execute("INSERT INTO gastos_fijos (nombre, activo) VALUES ('Alquiler local', 1)");
      crudo.execute("INSERT INTO gastos_fijos_montos (gasto_fijo_id, mes_anio, monto_centavos) VALUES (last_insert_rowid(), '2026-10', 45000000)");
      crudo.execute('PRAGMA user_version = 63');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final resumen = await fijosDelMes(db, '2026-10');
    expect(resumen.conceptos.where((c) => c.concepto.nombre == 'Alquiler local').single.montoCentavos, 45000000);
    final fijos = await cambiosDesde(db, tabla: 'gastos_fijos', desde: 0);
    expect(fijos.where((f) => f['nombre'] == 'Alquiler local').single['global_id'], isNotNull);
    final montos = await cambiosDesde(db, tabla: 'gastos_fijos_montos', desde: 0);
    expect(montos.single['global_id'], isNotNull);
    expect(montos.single['gasto_fijo_id_gid'], isNotNull, reason: 'el monto viaja con la identidad de su fijo');
  });
}
