// Prueba de upgrade REAL (v62 → v63: el rubro del comercio queda guardado) contra un archivo de verdad, mismo motivo que
// `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v62 real sube a v63: la configuración queda igual y el rubro arranca sin elegir', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v63_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.update(nueva.configuracionNegocioTabla).write(
          const ConfiguracionNegocioTablaCompanion(nombreComercio: Value('La Plazoleta'), pasoRedondeoCentavos: Value(5000)),
        );
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN rubro');
      crudo.execute('PRAGMA user_version = 62');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.nombreComercio, 'La Plazoleta');
    expect(config.pasoRedondeoCentavos, 5000);
    expect(config.rubro, '', reason: 'el rubro con que se armó un negocio viejo no se guardó nunca: no se adivina');
  });
}
