// Prueba de upgrade REAL (v31 → v32, `usuarios` se suma a la sincronización
// por Firestore — Bruno, 2026-09-18: "no debería tener que escanear ya, es
// innecesario") contra un archivo de verdad, no `NativeDatabase.memory()` —
// mismo motivo que `migracion_v30_test.dart`/`migracion_v31_test.dart`: en
// memoria siempre se pasa por `onCreate` (esquema más nuevo de una), nunca
// se ejercita `onUpgrade`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'una base v31 real, al abrirse con el código actual, sube a v32 y le pone '
    'global_id a los usuarios viejos',
    () async {
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v32_');
      final archivo = File('${carpeta.path}/base.sqlite');
      addTearDown(() => carpeta.delete(recursive: true));

      var db = AppDatabase(NativeDatabase(archivo));

      // `_seedDatosFijos` (onCreate) ya deja un usuario ("Bruno" o similar)
      // con `global_id` NULL — igual que la base real hoy. Se agrega un
      // segundo usuario para tener más de una fila que backfillear.
      final segundoUsuarioId = await db.into(db.usuarios).insert(
        UsuariosCompanion.insert(nombre: 'Empleado de prueba'),
      );

      await db.close();

      // El `onCreate` de arriba ya usa el esquema actual (v32), así que
      // `usuarios` ya tiene sus tres columnas de sync de fábrica — hay que
      // arrancárselas a mano antes de bajar `user_version` a 31, si no
      // `onUpgrade` fallaría con "duplicate column" al intentar agregar una
      // columna que ya está (mismo mecanismo — `CREATE TABLE ... AS SELECT`
      // de las columnas viejas vía `PRAGMA table_info` — que usa
      // `migracion_v30_test.dart`/`migracion_v31_test.dart`).
      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('PRAGMA foreign_keys = OFF');
        const columnasNuevas = {'global_id', 'origen_dispositivo', 'actualizado_en'};
        final infoColumnas = crudo.select('PRAGMA table_info(usuarios)');
        final columnasViejas = infoColumnas
            .map((fila) => fila['name'] as String)
            .where((nombre) => !columnasNuevas.contains(nombre))
            .join(', ');
        crudo.execute('CREATE TABLE usuarios_v31 AS SELECT $columnasViejas FROM usuarios');
        crudo.execute('DROP TABLE usuarios');
        crudo.execute('ALTER TABLE usuarios_v31 RENAME TO usuarios');
        crudo.execute('PRAGMA user_version = 31');
      } finally {
        crudo.close();
      }

      // Reabrimos con el código real — `onUpgrade(from: 31, to: 32)` corre.
      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      final usuarios = await db.select(db.usuarios).get();
      expect(usuarios.length, 2); // seed + el de arriba

      final segundoUsuario = await (db.select(
        db.usuarios,
      )..where((u) => u.id.equals(segundoUsuarioId))).getSingle();
      expect(segundoUsuario.globalId, isNotNull);
      expect(segundoUsuario.globalId, hasLength(32));
      expect(segundoUsuario.origenDispositivo, 'desktop');
      // Sin fecha propia: época 0, a propósito (mismo criterio que
      // categorías/proveedores/clientes en la migración v30→v31).
      expect(segundoUsuario.actualizadoEn, DateTime.fromMillisecondsSinceEpoch(0));

      // El usuario sembrado por `_seedDatosFijos` también se backfillea, con
      // un `global_id` propio (nunca el mismo que el de arriba).
      final usuarioSeed = await (db.select(
        db.usuarios,
      )..where((u) => u.id.equals(1))).getSingle();
      expect(usuarioSeed.globalId, isNotNull);
      expect(usuarioSeed.globalId, isNot(segundoUsuario.globalId));
    },
  );

  test(
    'bug real (2026-09-18, "quedó la pantalla en negro"): usuarios ya tiene las '
    'columnas de v32 pero user_version quedó atrasado — no explota con '
    '"duplicate column"',
    () async {
      // Reproduce exactamente lo que encontramos en la base real de Bruno:
      // una migración anterior alcanzó a agregar las columnas pero no llegó
      // a confirmar `user_version` (proceso cerrado a mitad de camino, o
      // similar) — el próximo arranque, con `from < 32` todavía verdadero,
      // intentaba agregar de nuevo columnas que ya estaban.
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v32_bug_');
      final archivo = File('${carpeta.path}/base.sqlite');
      addTearDown(() => carpeta.delete(recursive: true));

      var db = AppDatabase(NativeDatabase(archivo));
      // Una consulta real fuerza a drift a abrir la conexión de verdad
      // (`onCreate` corre recién en el primer uso, no en el constructor) —
      // sin esto, el archivo queda sin ninguna tabla.
      await db.select(db.usuarios).get();
      await db.close();

      // El esquema ya tiene las columnas (onCreate usa la versión actual) —
      // solo hace falta atrasar `user_version` a mano, sin tocar `usuarios`.
      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('PRAGMA user_version = 30');
      } finally {
        crudo.close();
      }

      // No debería lanzar — antes de este fix, esto tiraba
      // `SqliteException: duplicate column name: global_id`.
      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      final usuarios = await db.select(db.usuarios).get();
      expect(usuarios, isNotEmpty);
      expect(usuarios.every((u) => u.globalId != null), isTrue);
    },
  );
}
