// Prueba de upgrade REAL (v64 → v65: columnas de servicios e insumos, `docs/PLAN-SERVICIOS.md` etapa 2) contra un archivo de
// verdad, mismo motivo que `migracion_v47_test.dart`. Lo que importa: un almacén que actualiza no cambia (todo nace vacío o en
// false) y una base a medio migrar (alguna columna ya puesta) no se rompe.
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

/// Crea una base nueva, la baja a v64 sacando las columnas de la v65 (salvo [dejar]) y carga un producto con su movimiento.
Future<File> _baseV64(String nombre, {Set<String> dejar = const {}}) async {
  final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v65_$nombre');
  addTearDown(() => carpeta.delete(recursive: true));
  final archivo = File('${carpeta.path}/base.sqlite');
  final nueva = AppDatabase(NativeDatabase(archivo));
  await nueva.select(nueva.usuarios).get(); // abre (y crea) la base
  await nueva.close();

  final crudo = sqlite3.sqlite3.open(archivo.path);
  try {
    for (final c in _deProductos.where((c) => !dejar.contains(c))) {
      crudo.execute('ALTER TABLE productos DROP COLUMN $c');
    }
    for (final c in _deMovimientos.where((c) => !dejar.contains(c))) {
      crudo.execute('ALTER TABLE movimientos_de_stock DROP COLUMN $c');
    }
    if (!dejar.contains('valor_hora_centavos')) {
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN valor_hora_centavos');
    }
    final usuario = crudo.select('SELECT id FROM usuarios LIMIT 1').first['id'] as int;
    crudo.execute("INSERT INTO productos (nombre, precio_centavos, costo_centavos, stock) VALUES ('Yerba 1kg', 450000, 300000, 12)");
    crudo.execute(
      'INSERT INTO movimientos_de_stock (producto_id, usuario_id, tipo, cantidad, stock_anterior, stock_posterior) '
      "VALUES (last_insert_rowid(), $usuario, 'compra', 12, 0, 12)",
    );
    crudo.execute('PRAGMA user_version = 64');
  } finally {
    crudo.close();
  }
  return archivo;
}

void main() {
  test('una base v64 real sube a v65: el almacén sigue igual y las columnas nuevas nacen vacías', () async {
    final db = AppDatabase(NativeDatabase(await _baseV64('entera')));
    addTearDown(() => db.close());

    final yerba = await (db.select(db.productos)..where((p) => p.nombre.equals('Yerba 1kg'))).getSingle();
    expect(yerba.stock, 12);
    expect(yerba.precioCentavos, 450000);
    expect(yerba.esInsumo, isFalse);
    expect(yerba.esServicio, isFalse);
    expect(yerba.sumaManoDeObra, isFalse);
    expect(yerba.stockMilesimas, isNull);
    expect(yerba.recetaServicio, isNull);
    expect(yerba.gananciaBuscadaBp, isNull);

    final movimiento = await db.select(db.movimientosDeStock).getSingle();
    expect(movimiento.cantidad, 12);
    expect(movimiento.milesimas, isNull);
    expect(movimiento.milesimasPosterior, isNull);

    final columnasConfig =
        (await db.customSelect("SELECT name FROM pragma_table_info('configuracion_negocio_tabla')").get()).map((c) => c.data['name']);
    expect(columnasConfig, contains('valor_hora_centavos'));
  });

  test('una base a medio migrar (algunas columnas ya puestas) sube igual, sin chocar', () async {
    final db = AppDatabase(NativeDatabase(await _baseV64('a_medias', dejar: {'es_insumo', 'stock_milesimas', 'milesimas'})));
    addTearDown(() => db.close());

    final yerba = await (db.select(db.productos)..where((p) => p.nombre.equals('Yerba 1kg'))).getSingle();
    expect(yerba.esInsumo, isFalse);
    expect(yerba.duracionMinutos, isNull);
    expect((await db.select(db.movimientosDeStock).getSingle()).milesimasAnterior, isNull);
  });
}
