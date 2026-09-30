// Prueba de upgrade REAL (v36 → v37: completar el costo de ventas que
// quedaron sin costo con el costo ya cargado del producto — El dueño,
// 2026-09-26) contra un archivo de verdad, mismo motivo que
// `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'completa las ventas sin costo con el costo del producto; no pisa un costo guardado ni copia un \$0',
    () async {
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v37_');
      addTearDown(() => carpeta.delete(recursive: true));
      final archivo = File('${carpeta.path}/base.sqlite');

      var db = AppDatabase(NativeDatabase(archivo));
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final coca = await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Coca Lata', costoCentavos: const Value(119400)),
          );
      final lillo = await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Lillo suelto', costoCentavos: const Value(0)),
          );
      final queso = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Queso',
              esPesable: const Value(true),
              costoCentavos: const Value(1),
              costoPorKiloCentavos: const Value(600000),
            ),
          );
      Future<int> linea(int productoId, {int? costo, bool pesable = false}) async {
        final ventaId = await db.into(db.ventas).insert(
              VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 1, totalCentavos: 1),
            );
        return db.into(db.lineasDeVenta).insert(
              LineasDeVentaCompanion.insert(
                ventaId: ventaId,
                productoId: Value(productoId),
                nombreProductoFoto: 'x',
                esPesable: Value(pesable),
                gramos: Value(pesable ? 500 : null),
                precioUnitarioCentavos: 1,
                costoUnitarioCentavos: Value(costo),
              ),
            );
      }

      final cocaSinCosto = await linea(coca);
      final cocaConCosto = await linea(coca, costo: 100000);
      final lilloSinCosto = await linea(lillo);
      final quesoSinCosto = await linea(queso, pesable: true);
      await db.close();

      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('PRAGMA user_version = 36');
      } finally {
        crudo.close();
      }

      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());
      Future<int?> costo(int id) async =>
          (await (db.select(db.lineasDeVenta)..where((l) => l.id.equals(id))).getSingle()).costoUnitarioCentavos;

      expect(await costo(cocaSinCosto), 119400);
      expect(await costo(cocaConCosto), 100000); // costo-foto: no se pisa
      expect(await costo(lilloSinCosto), isNull); // $0 no cuenta como costo
      expect(await costo(quesoSinCosto), 600000); // pesable: por kilo
    },
  );
}
