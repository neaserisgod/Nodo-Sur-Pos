// Prueba de upgrade REAL (v66 → v67: la agenda de turnos, `docs/PLAN-SERVICIOS.md` etapa 4) contra un archivo de verdad, mismo
// motivo que `migracion_v47_test.dart`. La configuración y los productos de antes quedan igual; la tabla nace vacía.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v66 real sube a v67: horario y seña de fábrica, servicios sin seña y la agenda vacía', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v67_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE turnos');
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN horario_atencion');
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN config_sena');
      crudo.execute('ALTER TABLE productos DROP COLUMN pide_sena');
      crudo.execute("INSERT INTO productos (nombre, precio_centavos, es_servicio, duracion_minutos) VALUES ('Corte', 1000000, 1, 30)");
      crudo.execute('PRAGMA user_version = 66');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final corte = await (db.select(db.productos)..where((p) => p.nombre.equals('Corte'))).getSingle();
    expect(corte.pideSena, isFalse);
    expect(await db.select(db.turnos).get(), isEmpty);
    expect(await horarioActual(db), HorarioSemana.porDefecto);
    expect(await configSenaActual(db), ConfigSena.porDefecto);
    final indices = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'turnos'").get())
        .map((f) => f.data['name']);
    expect(indices, containsAll(['idx_turnos_global_id', 'idx_turnos_inicio']));
  });
}
