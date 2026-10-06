// Prueba de upgrade REAL (v54 → v55: seña de encargues) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v54 real sube a v55: los encargues que había quedan sin seña y se puede guardar una', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v55_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final usuarioId = await nueva.into(nueva.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await nueva.into(nueva.pendientes).insert(
      PendientesCompanion.insert(tipo: 'ENCARGUE', nombreLibre: const Value('María'), usuarioId: usuarioId),
    );
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE pendientes DROP COLUMN sena_centavos');
      crudo.execute('ALTER TABLE pendientes DROP COLUMN sena_es_efectivo');
      crudo.execute('PRAGMA user_version = 54');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final maria = (await db.select(db.pendientes).get()).single;
    expect(maria.nombreLibre, 'María');
    expect(maria.senaCentavos, 0);
    expect(maria.senaEsEfectivo, isTrue);

    await (db.update(db.pendientes)..where((p) => p.id.equals(maria.id))).write(
      const PendientesCompanion(senaCentavos: Value(200000), senaEsEfectivo: Value(false)),
    );
    final con = (await db.select(db.pendientes).get()).single;
    expect(con.senaCentavos, 200000);
    expect(con.senaEsEfectivo, isFalse);
  });
}
