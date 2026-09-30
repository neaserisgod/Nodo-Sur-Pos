// Prueba de upgrade REAL (v33 → v34, excedente de Mercado Pago por
// cigarrillos — El dueño, 2026-09-25) contra un archivo de verdad, no
// `NativeDatabase.memory()` — mismo motivo que `migracion_v33_test.dart`:
// en memoria siempre se pasa por `onCreate`, nunca se ejercita `onUpgrade`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  Future<File> baseV33() async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v34_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');

    final db = AppDatabase(NativeDatabase(archivo));
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    final sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 100000),
        );
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'PAGO_PROVEEDOR',
            montoCentavos: 50000,
          ),
        );
    await db.close();

    // El `onCreate` de arriba ya usa el esquema v34 — se sacan a mano las
    // dos columnas nuevas y se baja `user_version`, mismo mecanismo que las
    // pruebas de migración anteriores.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE sesiones_de_caja DROP COLUMN excedente_mp_cigarrillos_generado_centavos');
      crudo.execute('ALTER TABLE movimientos_de_caja DROP COLUMN uso_excedente_cigarrillos');
      crudo.execute('PRAGMA user_version = 33');
    } finally {
      crudo.close();
    }
    return archivo;
  }

  test(
    'una base v33 real sube a v34 sin tocar los datos: sesiones viejas con '
    'excedente null, movimientos viejos sin marca de uso',
    () async {
      final archivo = await baseV33();

      final db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      final sesion = await db.select(db.sesionesDeCaja).getSingle();
      expect(sesion.fondoInicialCentavos, 100000);
      expect(sesion.excedenteMpCigarrillosGeneradoCentavos, isNull);

      final movimiento = await db.select(db.movimientosDeCaja).getSingle();
      expect(movimiento.montoCentavos, 50000);
      expect(movimiento.usoExcedenteCigarrillos, isFalse);
    },
  );

  test(
    'si las columnas ya existían con user_version atrasado, el paso no '
    'explota con "duplicate column name" (mismo caso real que v31→v32)',
    () async {
      final archivo = await baseV33();
      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('ALTER TABLE sesiones_de_caja ADD COLUMN excedente_mp_cigarrillos_generado_centavos INTEGER');
        crudo.execute(
          'ALTER TABLE movimientos_de_caja ADD COLUMN uso_excedente_cigarrillos INTEGER NOT NULL DEFAULT 0',
        );
      } finally {
        crudo.close();
      }

      final db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      expect(await db.select(db.movimientosDeCaja).get(), hasLength(1));
    },
  );
}
