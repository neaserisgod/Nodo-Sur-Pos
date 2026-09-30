// Prueba de upgrade REAL (v38 → v39: cinco secciones dejan el menú —
// El dueño, 2026-09-26: "que apartados podemos resumir, agrupar o directamente
// eliminar") contra un archivo de verdad, mismo motivo que
// `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v38 real sube a v39: el menú queda sin Reportes, Equilibrio, Respaldo, Impresión ni Comparar precios', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v39_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.seccionesMenu).get(); // abre la base: corre onCreate
    await nueva.close();

    // El menú como estaba en la base real antes de este cambio.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('DELETE FROM secciones_menu');
      var orden = 0;
      for (final (clave, etiqueta) in [
        ('proveedores', 'Proveedores'),
        ('equilibrio', 'Equilibrio'),
        ('historial', 'Historial'),
        ('respaldo', 'Respaldo'),
        ('impresion', 'Impresión'),
        ('reportes', 'Reportes'),
        ('comparar_precios', 'Comparar precios'),
        ('separaciones', 'Separaciones'),
      ]) {
        crudo.execute(
          'INSERT INTO secciones_menu (clave, etiqueta, orden, visible) VALUES (?, ?, ?, 1)',
          [clave, etiqueta, orden++],
        );
      }
      crudo.execute('PRAGMA user_version = 38');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final claves = (await db.select(db.seccionesMenu).get()).map((s) => s.clave).toSet();
    expect(claves, {'proveedores', 'historial', 'separaciones'});
  });
}
