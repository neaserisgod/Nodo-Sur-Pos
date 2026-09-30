import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_secciones_menu.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  test('listarSecciones trae las 3 sembradas, en orden', () async {
    final secciones = await listarSecciones(db);
    expect(secciones, hasLength(3));
    expect(secciones.map((s) => s.orden), [0, 1, 2]);
    expect(secciones.first.clave, 'proveedores');
  });

  test('ocultarSeccion y mostrarSeccion alternan la visibilidad', () async {
    final proveedores = (await listarSecciones(
      db,
    )).firstWhere((s) => s.clave == 'proveedores');

    await ocultarSeccion(db, proveedores.id);
    expect(
      (await listarSecciones(
        db,
      )).firstWhere((s) => s.id == proveedores.id).visible,
      isFalse,
    );

    await mostrarSeccion(db, proveedores.id);
    expect(
      (await listarSecciones(
        db,
      )).firstWhere((s) => s.id == proveedores.id).visible,
      isTrue,
    );
  });

  test('reordenarSecciones aplica el nuevo orden completo', () async {
    final secciones = await listarSecciones(db);
    final idsInvertidos = secciones.reversed.map((s) => s.id).toList();

    await reordenarSecciones(db, idsInvertidos);

    final actualizado = await listarSecciones(db);
    expect(actualizado.map((s) => s.id).toList(), idsInvertidos);
  });

  test('listarSeccionesVisibles excluye las ocultas, en orden', () async {
    final secciones = await listarSecciones(db);
    final proveedores = secciones.firstWhere((s) => s.clave == 'proveedores');
    await ocultarSeccion(db, proveedores.id);

    final visibles = await listarSeccionesVisibles(db);

    expect(visibles.any((s) => s.clave == 'proveedores'), isFalse);
    // 3 sembradas - "proveedores" (recién ocultada acá).
    expect(visibles, hasLength(2));
  });
}
