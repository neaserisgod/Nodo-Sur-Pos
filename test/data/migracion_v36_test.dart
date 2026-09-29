// Prueba de upgrade REAL (v35 → v36, sección "Separaciones" en el menú —
// Bruno, 2026-09-26) contra un archivo de verdad, mismo motivo que
// `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  Future<File> baseV35({required bool conSeparaciones}) async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v36_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.seccionesMenu).get(); // abre la base: corre onCreate
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      if (!conSeparaciones) crudo.execute("DELETE FROM secciones_menu WHERE clave = 'separaciones'");
      // Un orden elegido a mano en Configuración, como en la base real.
      crudo.execute("UPDATE secciones_menu SET orden = 102 WHERE clave = 'historial'");
      crudo.execute('PRAGMA user_version = 35');
    } finally {
      crudo.close();
    }
    return archivo;
  }

  test('una base v35 real sube a v36: "Separaciones" aparece visible, al final del menú', () async {
    final db = AppDatabase(NativeDatabase(await baseV35(conSeparaciones: false)));
    addTearDown(() => db.close());

    final secciones = await (db.select(db.seccionesMenu)..orderBy([(s) => OrderingTerm.asc(s.orden)])).get();
    expect(secciones.last.clave, 'separaciones');
    expect(secciones.last.orden, 103);
    expect(secciones.last.visible, isTrue);
  });

  test('si ya estaba sembrada, no la duplica', () async {
    final db = AppDatabase(NativeDatabase(await baseV35(conSeparaciones: true)));
    addTearDown(() => db.close());

    final separaciones = await (db.select(db.seccionesMenu)..where((s) => s.clave.equals('separaciones'))).get();
    expect(separaciones, hasLength(1));
  });
}
