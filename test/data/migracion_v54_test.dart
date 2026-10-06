// Prueba de upgrade REAL (v53 → v54: logo del ticket) contra un archivo de verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v53 real sube a v54: la configuración queda igual, sin logo, y se puede guardar uno', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v54_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.into(nueva.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE configuracion_tabla DROP COLUMN logo_ticket');
      crudo.execute('PRAGMA user_version = 53');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect((await db.select(db.proveedores).get()).map((p) => p.codigo), contains('SE'));
    expect(await logoTicketGuardado(db), isNull);
    await configurarLogoTicket(db, Uint8List.fromList([1, 2, 3]));
    expect(await logoTicketGuardado(db), [1, 2, 3]);
  });
}
