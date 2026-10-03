import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/importacion_csv.dart';
import '../helpers/base_para_tests.dart';

const _encabezado = 'codigo_barras,nombre,proveedor,categoria,es_pesable,'
    'precio,costo,precio_por_kilo,costo_por_kilo,stock,stock_gramos';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  test('importa un producto por unidad nuevo', () async {
    final csv = '$_encabezado\n'
        '7790001,Coca-Cola 500ml,C,Bebidas,false,1120,800,,,20,\n';

    final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

    expect(r.insertados, 1);
    expect(r.actualizados, 0);
    expect(r.errores, isEmpty);

    final producto = await (db.select(db.productos)
          ..where((p) => p.codigoBarras.equals('7790001')))
        .getSingle();
    expect(producto.nombre, 'Coca-Cola 500ml');
    expect(producto.precioCentavos, 112000);
    expect(producto.costoCentavos, 80000);
    expect(producto.esPesable, false);
    expect(producto.stock, 20);
  });

  test('crea la categoría si no existe todavía', () async {
    final csv = '$_encabezado\n'
        ',Jamón crudo,F,Fiambres,true,,,3000,1800,,5000\n';

    await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

    final categoria =
        await (db.select(db.categorias)..where((c) => c.nombre.equals('Fiambres'))).getSingle();
    final producto = await (db.select(db.productos)
          ..where((p) => p.esVarios.equals(false)))
        .getSingle();
    expect(producto.categoriaId, categoria.id);
  });

  test('importa un producto pesable usando precio/costo por kilo', () async {
    final csv = '$_encabezado\n'
        ',Jamón crudo,F,Fiambres,true,,,3000,1800,,5000\n';

    final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

    expect(r.insertados, 1);
    final producto = await (db.select(db.productos)
          ..where((p) => p.esVarios.equals(false)))
        .getSingle();
    expect(producto.esPesable, true);
    expect(producto.precioPorKiloCentavos, 300000);
    expect(producto.costoPorKiloCentavos, 180000);
    expect(producto.stockGramos, 5000);
    expect(producto.precioCentavos, isNull);
  });

  test('acepta el precio en formato es-AR, igual que en toda la app', () async {
    final csv = '$_encabezado\n'
        '7790002,Producto caro,,,false,"1.500,50",,,,, \n';

    final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

    expect(r.errores, isEmpty);
    final producto = await (db.select(db.productos)
          ..where((p) => p.esVarios.equals(false)))
        .getSingle();
    expect(producto.precioCentavos, 150050);
  });

  group('errores por fila, sin abortar el resto del archivo', () {
    test('fila sin nombre: error, pero las demás filas se importan igual', () async {
      final csv = '$_encabezado\n'
          ',,,,false,1000,,,,, \n'
          '7790003,Producto válido,,,false,1000,,,,, \n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.insertados, 1);
      expect(r.errores, hasLength(1));
      expect(r.errores.single.fila, 2);
    });

    test('proveedor con código desconocido: error de fila', () async {
      final csv = '$_encabezado\n'
          '7790004,Producto,ZZ,,false,1000,,,,, \n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.insertados, 0);
      expect(r.errores, hasLength(1));
      expect(r.errores.single.mensaje, contains('ZZ'));
    });

    test('pesable sin precio_por_kilo: error, Regla 7 no permite un cero silencioso', () async {
      final csv = '$_encabezado\n'
          ',Fiambre sin precio,F,,true,,,,,, \n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.insertados, 0);
      expect(r.errores, hasLength(1));
    });

    test('no pesable sin precio: error', () async {
      final csv = '$_encabezado\n'
          '7790005,Producto sin precio,,,false,,,,,, \n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.insertados, 0);
      expect(r.errores, hasLength(1));
    });

    test('monto ilegible: error de fila con el texto original', () async {
      final csv = '$_encabezado\n'
          '7790006,Producto raro,,,false,no-es-un-precio,,,,, \n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.insertados, 0);
      expect(r.errores, hasLength(1));
    });
  });

  group('reimportar el mismo CSV actualiza en vez de duplicar', () {
    test('un producto ya existente (mismo código de barras) se actualiza, no se duplica', () async {
      final csvOriginal = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,,false,1120,800,,,20,\n';
      await importarProductosDesdeCsv(db, csvOriginal, usuarioId: usuarioId);

      final csvActualizado = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,,false,1200,850,,,20,\n';
      final r = await importarProductosDesdeCsv(db, csvActualizado, usuarioId: usuarioId);

      expect(r.insertados, 0);
      expect(r.actualizados, 1);

      final productos =
          await (db.select(db.productos)..where((p) => p.esVarios.equals(false))).get();
      expect(productos, hasLength(1));
      expect(productos.single.precioCentavos, 120000);
      expect(productos.single.costoCentavos, 85000);
    });

    test('un cambio de precio/costo por importación queda en el historial (Regla 14)', () async {
      final csvOriginal = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,,false,1120,800,,,20,\n';
      await importarProductosDesdeCsv(db, csvOriginal, usuarioId: usuarioId);

      final csvActualizado = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,,false,1200,850,,,20,\n';
      await importarProductosDesdeCsv(db, csvActualizado, usuarioId: usuarioId);

      final historial = await db.select(db.historialDePrecios).get();
      // Una fila por el alta inicial + una fila por el cambio.
      expect(historial, hasLength(2));
      expect(historial.last.precioCentavos, 120000);
      expect(historial.last.costoCentavos, 85000);
      expect(historial.last.usuarioId, usuarioId);
    });

    test('reimportar sin cambios no agrega ruido al historial', () async {
      final csv = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,,false,1120,800,,,20,\n';
      await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);
      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.actualizados, 1); // la fila se procesa igual...
      final historial = await db.select(db.historialDePrecios).get();
      expect(historial, hasLength(1)); // ...pero no hay nada nuevo que loguear
    });

    test('sin código de barras, matchea por nombre exacto', () async {
      final csv1 = '$_encabezado\n'
          ',Jamón crudo,F,,true,,,3000,1800,,5000\n';
      await importarProductosDesdeCsv(db, csv1, usuarioId: usuarioId);

      final csv2 = '$_encabezado\n'
          ',Jamón crudo,F,,true,,,3200,1900,,5000\n';
      final r = await importarProductosDesdeCsv(db, csv2, usuarioId: usuarioId);

      expect(r.actualizados, 1);
      final productos =
          await (db.select(db.productos)..where((p) => p.esVarios.equals(false))).get();
      expect(productos, hasLength(1));
      expect(productos.single.precioPorKiloCentavos, 320000);
    });
  });

  group('robustez (Fase 0.7)', () {
    test('una fila más corta que el encabezado no corta la importación', () async {
      final csv = '$_encabezado\n'
          '7790001,Coca-Cola 500ml,C,Bebidas,false,1120\n'
          '7790002,Sprite 500ml,C,Bebidas,false,1000,700,,,5,\n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.errores, isEmpty);
      expect(r.insertados, 2);
    });

    test('dos productos con el mismo nombre: error de esa fila, las demás siguen', () async {
      for (final codigo in ['1', '2']) {
        await db.into(db.productos).insert(
              ProductosCompanion.insert(nombre: 'Repetido', codigoBarras: Value(codigo)),
            );
      }
      final csv = '$_encabezado\n'
          ',Repetido,C,Bebidas,false,1000,,,,,\n'
          ',Otro,C,Bebidas,false,500,,,,,\n';

      final r = await importarProductosDesdeCsv(db, csv, usuarioId: usuarioId);

      expect(r.errores, hasLength(1));
      expect(r.errores.single.fila, 2);
      expect(r.insertados, 1);
    });

    test('reimportar sin la columna stock no deja el stock en cero', () async {
      await importarProductosDesdeCsv(db, '$_encabezado\n7790001,Coca,C,Bebidas,false,1120,800,,,20,\n', usuarioId: usuarioId);

      await importarProductosDesdeCsv(db, '$_encabezado\n7790001,Coca,C,Bebidas,false,1300,800,,,,\n', usuarioId: usuarioId);

      final p = await (db.select(db.productos)..where((x) => x.codigoBarras.equals('7790001'))).getSingle();
      expect(p.precioCentavos, 130000);
      expect(p.stock, 20);
    });
  });
}
