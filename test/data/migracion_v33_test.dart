// Prueba de upgrade REAL (v32 → v33, separa recargo de cigarrillos/paso de
// redondeo/producto de vuelto a `configuracion_negocio_tabla`, y suma
// `medios_de_pago` a la sincronización — El dueño, 2026-09-19: "que se puedan
// modificar las reglas del negocio... desde el celular") contra un archivo
// de verdad, no `NativeDatabase.memory()` — mismo motivo que
// `migracion_v32_test.dart`: en memoria siempre se pasa por `onCreate`
// (esquema más nuevo de una), nunca se ejercita `onUpgrade`.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/base_para_tests.dart';

void main() {
  test(
    'una base v32 real, al abrirse con el código actual, sube a v33: copia '
    'los valores REALES de configuracion_tabla (no los defaults) a '
    'configuracion_negocio_tabla, y le pone global_id fijo a medios_de_pago',
    () async {
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v33_');
      final archivo = File('${carpeta.path}/base.sqlite');
      addTearDown(() => carpeta.delete(recursive: true));

      var db = AppDatabase(NativeDatabase(archivo));

      // Valores NO-default a propósito — si la migración copiara los
      // defaults del esquema en vez de la fila real, este test no lo
      // notaría con los defaults de fábrica.
      final productoId = await db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Chicle', precioCentavos: const Value(50000)),
      );
      await (db.update(db.configuracionTabla)..where((c) => c.id.equals(1))).write(
        ConfiguracionTablaCompanion(
          recargoSueltoCentavos: const Value(7777),
          pasoRedondeoCentavos: const Value(12345),
          productoVueltoId: Value(productoId),
        ),
      );

      await db.close();

      // El `onCreate` de arriba ya usa el esquema actual (v33) — hay que
      // arrancarle a mano `configuracion_negocio_tabla` y las 3 columnas
      // nuevas de `medios_de_pago` antes de bajar `user_version` a 32,
      // mismo mecanismo que `migracion_v32_test.dart`.
      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('PRAGMA foreign_keys = OFF');
        crudo.execute('DROP TABLE configuracion_negocio_tabla');

        const columnasNuevas = {'global_id', 'origen_dispositivo', 'actualizado_en'};
        final infoColumnas = crudo.select('PRAGMA table_info(medios_de_pago)');
        final columnasViejas = infoColumnas
            .map((fila) => fila['name'] as String)
            .where((nombre) => !columnasNuevas.contains(nombre))
            .join(', ');
        crudo.execute('CREATE TABLE medios_de_pago_v32 AS SELECT $columnasViejas FROM medios_de_pago');
        crudo.execute('DROP TABLE medios_de_pago');
        crudo.execute('ALTER TABLE medios_de_pago_v32 RENAME TO medios_de_pago');

        crudo.execute('PRAGMA user_version = 32');
      } finally {
        crudo.close();
      }

      // Reabrimos con el código real — `onUpgrade(from: 32, to: 33)` corre.
      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      final filasNegocio = await db.select(db.configuracionNegocioTabla).get();
      expect(filasNegocio, hasLength(1));
      final negocio = filasNegocio.single;
      expect(negocio.recargoPrimerAtadoCentavos, 30000); // default, no se tocó
      expect(negocio.recargoSueltoCentavos, 7777); // el valor real, no el default (5000)
      expect(negocio.pasoRedondeoCentavos, 12345);
      expect(negocio.productoVueltoId, productoId);
      expect(negocio.globalId, hasLength(32));
      expect(negocio.origenDispositivo, 'desktop');
      expect(negocio.actualizadoEn, DateTime.fromMillisecondsSinceEpoch(0));

      final mediosPago = await (db.select(
        db.mediosDePago,
      )..orderBy([(m) => OrderingTerm.asc(m.orden)])).get();
      expect(mediosPago, hasLength(2));
      expect(mediosPago[0].nombre, 'Efectivo');
      expect(mediosPago[0].globalId, 'medio-pago-efectivo');
      expect(mediosPago[1].nombre, 'Mercado Pago');
      expect(mediosPago[1].globalId, 'medio-pago-virtual');
      for (final medio in mediosPago) {
        expect(medio.origenDispositivo, 'desktop');
        expect(medio.actualizadoEn, DateTime.fromMillisecondsSinceEpoch(0));
      }
    },
  );

  test(
    'medios_de_pago sembrados en un onCreate nuevo ya nacen con el mismo '
    'global_id fijo (converge con una base que suba por migración)',
    () async {
      final db = baseDeTest();
      addTearDown(() => db.close());

      final mediosPago = await (db.select(
        db.mediosDePago,
      )..orderBy([(m) => OrderingTerm.asc(m.orden)])).get();
      expect(mediosPago, hasLength(2));
      expect(mediosPago[0].globalId, 'medio-pago-efectivo');
      expect(mediosPago[1].globalId, 'medio-pago-virtual');
    },
  );
}
