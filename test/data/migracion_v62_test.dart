// Prueba de upgrade REAL (v61 → v62: los artículos de cada promo viajan con ella) contra un archivo de verdad, mismo motivo que
// `migracion_v47_test.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v61 real sube a v62: la promo vieja (sin global_id) queda lista para sincronizar con sus artículos', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v62_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final usuario = (await nueva.select(nueva.usuarios).get()).first.id;
    Future<int> producto(String n) => nueva.into(nueva.productos).insert(
          ProductosCompanion.insert(nombre: n, precioCentavos: const Value(300000), costoCentavos: const Value(200000), stock: const Value(5)),
        );
    final a = await producto('Yerba');
    final b = await producto('Galletitas');
    final promo = await guardarPromo(nueva, nombre: 'Merienda', articulos: [(productoId: a, cantidad: 1), (productoId: b, cantidad: 2)], gananciaBp: 3000, usuarioId: usuario);
    await nueva.close();

    // Como estaba en la v61: sin la columna, y la promo y sus artículos sin global_id (así las creaba `guardarPromo`).
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE productos DROP COLUMN componentes_promo');
      crudo.execute('UPDATE productos SET global_id = NULL WHERE id IN ($a, $b, $promo)');
      crudo.execute('PRAGMA user_version = 61');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final filas = await cambiosDesde(db, tabla: 'productos', desde: 0);
    final laPromo = filas.singleWhere((f) => f['id'] == promo);
    expect(laPromo['global_id'], isNotNull);
    final componentes = jsonDecode(laPromo['componentes_promo'] as String) as List;
    expect(componentes, hasLength(2));
    final gids = {for (final f in filas) f['id']: f['global_id']};
    expect(componentes.map((c) => (c as Map)['gid']), [gids[a], gids[b]]);
  });
}
