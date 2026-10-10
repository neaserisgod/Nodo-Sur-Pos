// Prueba de upgrade REAL (v65 → v66: la Agenda, `docs/PLAN-SERVICIOS.md` etapa 4) contra un archivo de verdad, mismo motivo que
// `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _deConfig = [
  'horario_atencion',
  'paso_turnos_minutos',
  'sena_modo',
  'sena_porcentaje',
  'sena_monto_fijo_centavos',
  'sena_devolver_al_cancelar',
  'alias_sena',
  'titular_sena',
];

void main() {
  test('una base v65 real sube a v66: aparece la agenda vacía y la configuración con sus valores de arranque', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v66_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    // Como estaba en la v65: sin la tabla de turnos ni las columnas nuevas, con un servicio de antes.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DROP TABLE turnos');
      for (final c in _deConfig) {
        crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN $c');
      }
      crudo.execute('ALTER TABLE productos DROP COLUMN pide_sena');
      crudo.execute(
        "INSERT INTO productos (nombre, precio_centavos, costo_centavos, stock, es_servicio, duracion_minutos) VALUES ('Semipermanente', 1800000, 0, 0, 1, 60)",
      );
      crudo.execute('PRAGMA user_version = 65');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final semi = await (db.select(db.productos)..where((p) => p.nombre.equals('Semipermanente'))).getSingle();
    expect(semi.esServicio, isTrue);
    expect(semi.pideSena, isFalse);
    expect(await db.select(db.turnos).get(), isEmpty);

    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.pasoTurnosMinutos, 15);
    expect(config.senaModo, 'ALGUNOS');
    expect(config.senaPorcentaje, 30);
    expect(config.senaDevolverAlCancelar, isFalse);
    expect(config.horarioAtencion, isNull);

    final indices = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'turnos'").get())
        .map((f) => f.data['name'] as String);
    expect(indices, contains('idx_turnos_global_id'));
  });
}
