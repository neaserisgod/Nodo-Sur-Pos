// Prueba de upgrade REAL (v46 → v47: encargues por apartado) contra un archivo de verdad, mismo motivo que
// `migracion_v39_test.dart`: lo que se rompe en una base vieja no se ve en una base nueva de test.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v46 real sube a v47: encargues con líneas, borrador con encargue y la sección del menú; no pierde lo que había', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v47_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final usuarioId = await nueva.into(nueva.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await nueva.close();

    // Como estaba antes: sin las dos columnas nuevas, sin la sección, con un encargue viejo de texto libre.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE pendientes DROP COLUMN lineas_json');
      crudo.execute('ALTER TABLE ventas_abiertas DROP COLUMN encargue_id');
      crudo.execute("DELETE FROM secciones_menu WHERE clave = 'encargues'");
      crudo.execute(
        "INSERT INTO pendientes (tipo, nombre_libre, descripcion, estado, usuario_id) VALUES ('ENCARGUE', 'Doña Rosa', '2 gaseosas', 'PENDIENTE', ?)",
        [usuarioId],
      );
      crudo.execute('PRAGMA user_version = 46');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final claves = (await db.select(db.seccionesMenu).get()).map((s) => s.clave);
    expect(claves, contains('encargues'));
    final viejo = (await db.select(db.pendientes).get()).single;
    expect(viejo.descripcion, '2 gaseosas', reason: 'el encargue de texto libre sigue ahí');
    expect(viejo.lineasJson, isNull);
    final columnasAbiertas = (await db.customSelect("SELECT name FROM pragma_table_info('ventas_abiertas')").get()).map((c) => c.data['name']);
    expect(columnasAbiertas, contains('encargue_id'));
  });
}
