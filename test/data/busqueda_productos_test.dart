import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/busqueda_productos.dart';
import 'package:la_plazoleta/data/database.dart';
import '../helpers/base_para_tests.dart';

Future<Producto> _crearProducto(
  AppDatabase db, {
  required String nombre,
  String? codigoBarras,
  bool esPesable = false,
  bool activo = true,
  bool esVarios = false,
  // Con stock por default: la mayoría de estos tests no son sobre stock,
  // son sobre matching de texto/código — el default tiene que ser
  // "vendible" para no confundir esos dos motivos de fallo. Los tests que
  // sí son sobre stock lo pasan en 0 explícitamente.
  int stock = 10,
  int stockGramos = 1000,
}) async {
  final id = await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: nombre,
          codigoBarras: Value(codigoBarras),
          esPesable: Value(esPesable),
          esVarios: Value(esVarios),
          precioCentavos: esPesable ? const Value(null) : const Value(100000),
          precioPorKiloCentavos: esPesable
              ? const Value(300000)
              : const Value(null),
          activo: Value(activo),
          stock: Value(stock),
          stockGramos: esPesable ? Value(stockGramos) : const Value(null),
        ),
      );
  return (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
}

void main() {
  group('interpretarTexto', () {
    test('texto simple: gramos null', () {
      final r = interpretarTexto('coca cola');
      expect(r.gramos, isNull);
      expect(r.texto, 'coca cola');
    });

    test('número + espacio + nombre: extrae gramos', () {
      final r = interpretarTexto('200 queso barra');
      expect(r.gramos, 200);
      expect(r.texto, 'queso barra');
    });

    test('recorta espacios sobrantes', () {
      final r = interpretarTexto('  coca  ');
      expect(r.texto, 'coca');
    });
  });

  group('buscarProductos', () {
    late AppDatabase db;
    setUp(() => db = baseDeTest());
    tearDown(() => db.close());

    test('ignora mayúsculas y acentos', () async {
      await _crearProducto(db, nombre: 'Jamón Crudo');
      final catalogo = await db.select(db.productos).get();

      final r = buscarProductos(
        catalogo: catalogo,
        textoBuscado: 'JAMON crudo',
      );
      expect(r, hasLength(1));
      expect(r.single.nombre, 'Jamón Crudo');
    });

    test(
      'coincidencia exacta de código de barras gana sola, aunque el nombre matchee otra cosa',
      () async {
        await _crearProducto(
          db,
          nombre: 'Coca-Cola 500ml',
          codigoBarras: '7790001',
        );
        await _crearProducto(
          db,
          nombre: 'Coca-Cola 1.5L',
          codigoBarras: '7790002',
        );
        final catalogo = await db.select(db.productos).get();

        final r = buscarProductos(catalogo: catalogo, textoBuscado: '7790001');
        expect(r, hasLength(1));
        expect(r.single.codigoBarras, '7790001');
      },
    );

    test('"200 queso barra": extrae gramos y filtra solo pesables', () async {
      await _crearProducto(db, nombre: 'Queso barra', esPesable: true);
      await _crearProducto(
        db,
        nombre: 'Queso rallado',
        esPesable: false,
      ); // no debe aparecer
      final catalogo = await db.select(db.productos).get();

      final r = buscarProductos(catalogo: catalogo, textoBuscado: '200 queso');
      expect(r, hasLength(1));
      expect(r.single.esPesable, true);
    });

    test(
      'con gramos, un producto no pesable nunca aparece aunque el nombre matchee',
      () async {
        await _crearProducto(db, nombre: 'Queso rallado', esPesable: false);
        final catalogo = await db.select(db.productos).get();

        final r = buscarProductos(
          catalogo: catalogo,
          textoBuscado: '150 queso',
        );
        expect(r, isEmpty);
      },
    );

    test('"7 up": si ningún pesable coincide, el número es parte del nombre (Fase 0.8)', () async {
      await _crearProducto(db, nombre: '7 Up 500ml');
      await _crearProducto(db, nombre: 'Queso barra', esPesable: true);
      final catalogo = await db.select(db.productos).get();

      final r = buscarProductos(catalogo: catalogo, textoBuscado: '7 up');

      expect(r.map((p) => p.nombre), ['7 Up 500ml']);
    });

    test('productos inactivos no aparecen en la búsqueda', () async {
      await _crearProducto(db, nombre: 'Discontinuado', activo: false);
      final catalogo = await db.select(db.productos).get();

      final r = buscarProductos(
        catalogo: catalogo,
        textoBuscado: 'discontinuado',
      );
      expect(r, isEmpty);
    });

    test('respeta el límite de resultados', () async {
      for (var i = 0; i < 10; i++) {
        await _crearProducto(db, nombre: 'Producto $i');
      }
      final catalogo = await db.select(db.productos).get();

      final r = buscarProductos(
        catalogo: catalogo,
        textoBuscado: 'producto',
        limite: 8,
      );
      expect(r, hasLength(8));
    });

    test(
      'texto vacío no devuelve nada (evita listar todo el catálogo)',
      () async {
        await _crearProducto(db, nombre: 'Algo');
        final catalogo = await db.select(db.productos).get();

        expect(buscarProductos(catalogo: catalogo, textoBuscado: ''), isEmpty);
        expect(
          buscarProductos(catalogo: catalogo, textoBuscado: '   '),
          isEmpty,
        );
      },
    );

    test(
      'sin coincidencias: lista vacía (la UI decide mostrar alta rápida)',
      () async {
        await _crearProducto(db, nombre: 'Algo');
        final catalogo = await db.select(db.productos).get();

        expect(
          buscarProductos(catalogo: catalogo, textoBuscado: 'xyz'),
          isEmpty,
        );
      },
    );

    group('sin stock, no aparece en ventas (Dueño, 2026-09-06)', () {
      test(
        'por nombre: un producto con stock 0 no aparece en la búsqueda',
        () async {
          await _crearProducto(db, nombre: 'Sin stock', stock: 0);
          final catalogo = await db.select(db.productos).get();

          expect(
            buscarProductos(catalogo: catalogo, textoBuscado: 'sin stock'),
            isEmpty,
          );
        },
      );

      test('por código de barras: tampoco gana si tiene stock 0', () async {
        await _crearProducto(
          db,
          nombre: 'Sin stock',
          codigoBarras: '123',
          stock: 0,
        );
        final catalogo = await db.select(db.productos).get();

        expect(
          buscarProductos(catalogo: catalogo, textoBuscado: '123'),
          isEmpty,
        );
      });

      test('stock negativo tampoco aparece (mismo criterio que 0)', () async {
        await _crearProducto(db, nombre: 'Stock negativo', stock: -3);
        final catalogo = await db.select(db.productos).get();

        expect(
          buscarProductos(catalogo: catalogo, textoBuscado: 'stock negativo'),
          isEmpty,
        );
      });

      test('pesable con stockGramos 0 no aparece', () async {
        await _crearProducto(
          db,
          nombre: 'Queso sin stock',
          esPesable: true,
          stockGramos: 0,
        );
        final catalogo = await db.select(db.productos).get();

        expect(
          buscarProductos(catalogo: catalogo, textoBuscado: '200 queso'),
          isEmpty,
        );
      });

      test(
        '"Varios" aparece igual con stock 0 — no tiene stock real (Regla 5/9)',
        () async {
          // "Varios" ya viene seedeado (esVarios: true, stock: 0 por
          // default) — no hace falta crear uno, alcanza con confirmar que
          // el seed no queda afuera por el nuevo filtro.
          final catalogo = await db.select(db.productos).get();
          final varios = catalogo.singleWhere((p) => p.esVarios);
          expect(varios.stock, 0);

          expect(
            buscarProductos(catalogo: catalogo, textoBuscado: 'varios'),
            contains(varios),
          );
        },
      );

      test(
        'con stock, aparece normalmente (no rompe el caso de siempre)',
        () async {
          await _crearProducto(db, nombre: 'Con stock', stock: 5);
          final catalogo = await db.select(db.productos).get();

          expect(
            buscarProductos(catalogo: catalogo, textoBuscado: 'con stock'),
            hasLength(1),
          );
        },
      );
    });
  });
}
