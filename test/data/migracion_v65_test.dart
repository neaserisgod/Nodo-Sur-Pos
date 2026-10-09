// Prueba de upgrade REAL (v64 → v65: columnas de servicios e insumos, `docs/PLAN-SERVICIOS.md` etapa 2) contra un archivo de
// verdad, mismo motivo que `migracion_v47_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _deProductos = [
  'es_insumo',
  'unidad_insumo',
  'contenido_envase_milesimas',
  'stock_milesimas',
  'stock_minimo_milesimas',
  'es_servicio',
  'duracion_minutos',
  'receta_servicio',
  'suma_mano_de_obra',
  'ganancia_buscada_bp',
];
const _deMovimientos = ['milesimas', 'milesimas_anterior', 'milesimas_posterior'];

void main() {
  test('una base v64 real sube a v65: los productos de siempre siguen y no son ni insumo ni servicio', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v65_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
    await nueva.close();

    // Como estaba en la v64: sin las columnas nuevas, con un producto y un movimiento de stock de antes.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      for (final c in _deProductos) {
        crudo.execute('ALTER TABLE productos DROP COLUMN $c');
      }
      for (final c in _deMovimientos) {
        crudo.execute('ALTER TABLE movimientos_de_stock DROP COLUMN $c');
      }
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN valor_hora_centavos');
      crudo.execute(
        "INSERT INTO productos (nombre, precio_centavos, costo_centavos, stock) VALUES ('Yerba Playadito 1 kg', 520000, 380000, 12)",
      );
      crudo.execute('PRAGMA user_version = 64');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final yerba = await (db.select(db.productos)..where((p) => p.nombre.equals('Yerba Playadito 1 kg'))).getSingle();
    expect(yerba.stock, 12);
    expect(yerba.esInsumo, isFalse);
    expect(yerba.esServicio, isFalse);
    expect(yerba.sumaManoDeObra, isFalse);
    expect(yerba.stockMilesimas, isNull);
    expect(yerba.recetaServicio, isNull);

    Future<Set<String>> columnas(String tabla) async =>
        (await db.customSelect("SELECT name FROM pragma_table_info('$tabla')").get()).map((c) => c.data['name'] as String).toSet();
    expect(await columnas('productos'), containsAll(_deProductos));
    expect(await columnas('movimientos_de_stock'), containsAll(_deMovimientos));
    expect(await columnas('configuracion_negocio_tabla'), contains('valor_hora_centavos'));
  });
}
