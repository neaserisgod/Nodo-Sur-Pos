// Prueba de upgrade REAL (v45 → v46: el porcentaje por proveedor y el de
// referencia por categoría pasan de markup sobre el costo a ganancia sobre el
// precio) contra un archivo de verdad, mismo motivo que `migracion_v45_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/ganancia.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/base_para_tests.dart';

Future<File> _baseV45() async {
  final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v46_');
  addTearDown(() => carpeta.delete(recursive: true));
  final archivo = File('${carpeta.path}/base.sqlite');
  final nueva = AppDatabase(NativeDatabase(archivo), sembrarCatalogoDeTest);
  await nueva.select(nueva.proveedores).get();
  await nueva.close();
  final crudo = sqlite3.sqlite3.open(archivo.path);
  try {
    crudo.execute('UPDATE proveedores SET markup_bp = NULL, actualizado_en = 1234');
    crudo.execute("UPDATE proveedores SET markup_bp = 5000 WHERE codigo = 'S'");
    crudo.execute("UPDATE proveedores SET markup_bp = 10000 WHERE codigo = 'SC'");
    crudo.execute("UPDATE categorias SET markup_default_bp = 7000, actualizado_en = 1234 WHERE nombre = 'Bebidas'");
    crudo.execute("UPDATE categorias SET markup_default_bp = 0 WHERE nombre = 'Vinos'");
    crudo.execute('PRAGMA user_version = 45');
  } finally {
    crudo.close();
  }
  return archivo;
}

void main() {
  test('una base v45 real sube a v46: cada markup guardado pasa a su ganancia equivalente', () async {
    final archivo = await _baseV45();
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());

    final proveedores = await db.select(db.proveedores).get();
    int? bp(String codigo) => proveedores.firstWhere((p) => p.codigo == codigo).markupBp;
    expect(bp('S'), 3333); // 50% de markup = 33,33% de ganancia
    expect(bp('SC'), 5000); // 100% de markup = 50% de ganancia
    expect(proveedores.where((p) => p.codigo != 'S' && p.codigo != 'SC').every((p) => p.markupBp == null), isTrue);

    final categorias = await db.select(db.categorias).get();
    int ref(String nombre) => categorias.firstWhere((c) => c.nombre == nombre).markupDefaultBp;
    expect(ref('Bebidas'), 4118); // 70% de markup = 41,18% de ganancia
    expect(ref('Vinos'), 0);
  });

  test('los precios no se mueven: costo + markup viejo = costo / (1 − ganancia convertida)', () async {
    final archivo = await _baseV45();
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());

    final bp = (await db.select(db.proveedores).get()).firstWhere((p) => p.codigo == 'S').markupBp!;
    // Antes: $1.000 × 1,5 = $1.500. Ahora, con el % convertido, el mismo precio.
    expect(precioDesdeCostoYGanancia(100000, bp), 150000);
  });

  test('no se toca la fecha de modificación: nada se reenvía por sync por esta migración', () async {
    final archivo = await _baseV45();
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());

    final proveedores = await db.select(db.proveedores).get();
    expect(proveedores.every((p) => p.actualizadoEn!.millisecondsSinceEpoch == 1234 * 1000), isTrue);
  });
}
