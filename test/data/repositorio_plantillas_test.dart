import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_plantillas.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<List<String>> nombresDeCategorias() async =>
      (await (db.select(db.categorias)..orderBy([(c) => OrderingTerm.asc(c.nombre)])).get()).map((c) => c.nombre).toList();
  Future<List<String>> nombresDeGastosFijos() async =>
      (await db.select(db.gastosFijos).get()).map((g) => g.nombre).toList();

  group('aplicarPlantillaRubro', () {
    test('una base nueva de verdad arranca sin categorías, proveedores ni gastos fijos de nadie', () async {
      expect(await db.select(db.categorias).get(), isEmpty);
      expect(await db.select(db.proveedores).get(), isEmpty);
      expect(await db.select(db.gastosFijos).get(), isEmpty);
    });

    test('carga las categorías y los gastos fijos de la plantilla', () async {
      final almacen = PlantillaRubro.desdeClave('almacen')!;
      final resultado = await aplicarPlantillaRubro(db, almacen);

      expect(await nombresDeCategorias(), almacen.categorias.map((c) => c.nombre).toList()..sort());
      expect(await nombresDeGastosFijos(), almacen.gastosFijos);
      expect(resultado.categoriasNuevas, almacen.categorias.length);
      expect(resultado.gastosFijosNuevos, almacen.gastosFijos.length);
    });

    test('aplicarla dos veces no duplica nada', () async {
      final kiosco = PlantillaRubro.desdeClave('kiosco')!;
      await aplicarPlantillaRubro(db, kiosco);
      final segunda = await aplicarPlantillaRubro(db, kiosco);

      expect(segunda.categoriasNuevas, 0);
      expect(segunda.gastosFijosNuevos, 0);
      expect((await db.select(db.categorias).get()).length, kiosco.categorias.length);
      expect((await db.select(db.gastosFijos).get()).length, kiosco.gastosFijos.length);
    });

    test('respeta lo que el comercio ya tenía: no lo duplica ni le pisa el margen de referencia', () async {
      await db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: 'golosinas', markupDefaultBp: const Value(6500)));
      await aplicarPlantillaRubro(db, PlantillaRubro.desdeClave('kiosco')!);

      final golosinas = await (db.select(db.categorias)..where((c) => c.nombre.lower().equals('golosinas'))).get();
      expect(golosinas, hasLength(1));
      expect(golosinas.single.nombre, 'golosinas');
      expect(golosinas.single.markupDefaultBp, 6500);
    });

    test('la plantilla "otro" no agrega categorías', () async {
      final resultado = await aplicarPlantillaRubro(db, PlantillaRubro.otro);
      expect(resultado.categoriasNuevas, 0);
      expect(await db.select(db.categorias).get(), isEmpty);
    });

    test('aplicar dos rubros distintos suma las categorías sin repetir las que comparten', () async {
      final kiosco = PlantillaRubro.desdeClave('kiosco')!;
      final almacen = PlantillaRubro.desdeClave('almacen')!;
      await aplicarPlantillaRubro(db, kiosco);
      await aplicarPlantillaRubro(db, almacen);

      final esperadas = {...kiosco.categorias.map((c) => c.nombre.toLowerCase()), ...almacen.categorias.map((c) => c.nombre.toLowerCase())};
      final guardadas = (await db.select(db.categorias).get()).map((c) => c.nombre.toLowerCase()).toList();
      expect(guardadas.toSet(), esperadas);
      expect(guardadas.length, esperadas.length);
    });
  });
}
