import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart' show crearProveedor;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/edicion_masiva_precios.dart';
import 'package:la_plazoleta/domain/edicion_masiva_stock.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  });
  tearDown(() => db.close());

  group('crearProducto', () {
    test('crea el producto y una fila de historial con la foto inicial', () async {
      final categoriaId =
          (await (db.select(db.categorias)..where((c) => c.nombre.equals('Almacén'))).getSingle())
              .id;

      final id = await crearProducto(
        db,
        nombre: 'Coca-Cola 500ml',
        categoriaId: categoriaId,
        precioCentavos: 150000,
        costoCentavos: 100000,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.nombre, 'Coca-Cola 500ml');

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(1));
      expect(historial.single.precioCentavos, 150000);
      expect(historial.single.usuarioId, usuarioId);
    });

    test('un producto pesable sin precio_por_kilo tira error (Regla 7)', () async {
      expect(
        () => crearProducto(
          db,
          nombre: 'Jamón',
          esPesable: true,
          usuarioId: usuarioId,
        ),
        throwsArgumentError,
      );
    });

    test('un código de barras repetido tira un error de negocio claro, no la excepción cruda de sqlite', () async {
      await crearProducto(
        db,
        nombre: 'Coca-Cola 500ml',
        codigoBarras: '7790001',
        precioCentavos: 150000,
        usuarioId: usuarioId,
      );

      expect(
        () => crearProducto(
          db,
          nombre: 'Otro producto',
          codigoBarras: '7790001',
          precioCentavos: 100000,
          usuarioId: usuarioId,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Coca-Cola 500ml'),
          ),
        ),
      );
    });

    test('el aviso de código repetido avisa si el producto que ya lo tiene está dado de baja', () async {
      final id = await crearProducto(
        db,
        nombre: 'Producto viejo',
        codigoBarras: '7790002',
        precioCentavos: 100000,
        usuarioId: usuarioId,
      );
      await cambiarActivo(db, id: id, activo: false);

      expect(
        () => crearProducto(
          db,
          nombre: 'Nuevo con el mismo código',
          codigoBarras: '7790002',
          precioCentavos: 100000,
          usuarioId: usuarioId,
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', contains('dado de baja')),
        ),
      );
    });
  });

  group('actualizarProducto', () {
    test('cambiar el precio agrega una fila nueva al historial', () async {
      final id = await crearProducto(
        db,
        nombre: 'Coca-Cola',
        precioCentavos: 150000,
        costoCentavos: 100000,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Coca-Cola',
        esPesable: false,
        precioCentavos: 160000,
        costoCentavos: 100000,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(2));
      expect(historial.first.precioCentavos, 160000); // orden desc por fecha
    });

    test('cambiar el código a uno que ya usa otro producto tira error, no la excepción cruda', () async {
      await crearProducto(
        db,
        nombre: 'Producto A',
        codigoBarras: '7790010',
        precioCentavos: 100000,
        usuarioId: usuarioId,
      );
      final idB = await crearProducto(
        db,
        nombre: 'Producto B',
        codigoBarras: '7790011',
        precioCentavos: 100000,
        usuarioId: usuarioId,
      );

      expect(
        () => actualizarProducto(
          db,
          id: idB,
          nombre: 'Producto B',
          codigoBarras: '7790010', // el código de "Producto A"
          esPesable: false,
          precioCentavos: 100000,
          stock: 0,
          activo: true,
          usuarioId: usuarioId,
        ),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', contains('Producto A')),
        ),
      );
    });

    test('guardar sin cambiar el código (aunque otro producto no lo tenga) nunca choca contra sí mismo', () async {
      final id = await crearProducto(
        db,
        nombre: 'Coca-Cola',
        codigoBarras: '7790020',
        precioCentavos: 150000,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Coca-Cola 500ml',
        codigoBarras: '7790020', // mismo código de siempre
        esPesable: false,
        precioCentavos: 150000,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.nombre, 'Coca-Cola 500ml');
    });

    test('actualizar sin cambiar precio ni costo no agrega ruido al historial', () async {
      final id = await crearProducto(
        db,
        nombre: 'Coca-Cola',
        precioCentavos: 150000,
        costoCentavos: 100000,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Coca-Cola 500ml', // cambia el nombre, no el precio/costo
        esPesable: false,
        precioCentavos: 150000,
        costoCentavos: 100000,
        stock: 5,
        activo: true,
        usuarioId: usuarioId,
      );

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(1));
    });

    test('completar el costo de un producto de alta rápida sí queda en historial', () async {
      final id = await crearProducto(
        db,
        nombre: 'Producto escaneado',
        precioCentavos: 50000,
        usuarioId: usuarioId,
        // sin costo: como en el alta rápida de la fase 3
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Producto escaneado',
        esPesable: false,
        precioCentavos: 50000,
        costoCentavos: 30000, // ahora sí se completa
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(2));
      expect(historial.first.costoCentavos, 30000);
    });
  });

  group('registrarAjusteDeStock (vía actualizarProducto) — Regla 8', () {
    test('cambiar el stock en unidades inserta un movimiento AJUSTE', () async {
      final id = await crearProducto(
        db,
        nombre: 'Fideos',
        precioCentavos: 1000,
        stock: 10,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Fideos',
        esPesable: false,
        precioCentavos: 1000,
        stock: 7,
        activo: true,
        usuarioId: usuarioId,
      );

      final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();
      expect(movimientos, hasLength(1));
      expect(movimientos.single.tipo, 'AJUSTE');
      expect(movimientos.single.stockAnterior, 10);
      expect(movimientos.single.stockPosterior, 7);
      expect(movimientos.single.usuarioId, usuarioId);
      expect(movimientos.single.ventaId, isNull);
    });

    test('cambiar el stock en gramos de un pesable inserta el movimiento con los campos de gramos', () async {
      final id = await crearProducto(
        db,
        nombre: 'Jamón',
        esPesable: true,
        precioPorKiloCentavos: 8000000,
        stockGramos: 5000,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Jamón',
        esPesable: true,
        precioPorKiloCentavos: 8000000,
        stock: 0,
        stockGramos: 4200,
        activo: true,
        usuarioId: usuarioId,
      );

      final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();
      expect(movimientos, hasLength(1));
      expect(movimientos.single.gramosAnterior, 5000);
      expect(movimientos.single.gramosPosterior, 4200);
      expect(movimientos.single.stockAnterior, isNull);
    });

    test('guardar sin cambiar el stock no agrega ningún movimiento', () async {
      final id = await crearProducto(
        db,
        nombre: 'Fideos',
        precioCentavos: 1000,
        stock: 10,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Fideos 500g', // cambia el nombre, no el stock
        esPesable: false,
        precioCentavos: 1200,
        stock: 10,
        activo: true,
        usuarioId: usuarioId,
      );

      final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();
      expect(movimientos, isEmpty);
    });

    test('el motivo se guarda si se pasa, y queda null si no', () async {
      final id = await crearProducto(
        db,
        nombre: 'Fideos',
        precioCentavos: 1000,
        stock: 10,
        usuarioId: usuarioId,
      );

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Fideos',
        esPesable: false,
        precioCentavos: 1000,
        stock: 8,
        activo: true,
        usuarioId: usuarioId,
        motivoAjusteStock: 'Conteo físico',
      );

      final movimiento =
          await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
      expect(movimiento.motivo, 'Conteo físico');
    });
  });

  group('cambiarActivo — nunca hay borrado real', () {
    test('desactiva un producto sin borrarlo', () async {
      final id = await crearProducto(db, nombre: 'Producto', precioCentavos: 1000, usuarioId: usuarioId);

      await cambiarActivo(db, id: id, activo: false);

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.activo, false);
      // sigue existiendo la fila, nada se borró
      expect(await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingleOrNull(), isNotNull);
    });
  });

  group('listarProductos — filtros', () {
    test('por defecto no trae "Varios" ni inactivos', () async {
      final id = await crearProducto(db, nombre: 'Activo', precioCentavos: 1000, usuarioId: usuarioId);
      final idInactivo =
          await crearProducto(db, nombre: 'Inactivo', precioCentavos: 1000, usuarioId: usuarioId);
      await cambiarActivo(db, id: idInactivo, activo: false);

      final productos = await listarProductos(db);

      expect(productos.any((p) => p.esVarios), false);
      expect(productos.map((p) => p.id), contains(id));
      expect(productos.map((p) => p.id), isNot(contains(idInactivo)));
    });

    test('busqueda ignora mayúsculas y acentos, igual que en la venta', () async {
      await crearProducto(db, nombre: 'Jamón Crudo', precioCentavos: 1000, usuarioId: usuarioId);

      final productos = await listarProductos(db, busqueda: 'JAMON crudo');
      expect(productos, hasLength(1));
    });

    test('filtra por categoría', () async {
      final almacen =
          (await (db.select(db.categorias)..where((c) => c.nombre.equals('Almacén'))).getSingle()).id;
      final bebidas =
          (await (db.select(db.categorias)..where((c) => c.nombre.equals('Bebidas'))).getSingle()).id;

      await crearProducto(db, nombre: 'A', categoriaId: almacen, precioCentavos: 1000, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'B', categoriaId: bebidas, precioCentavos: 1000, usuarioId: usuarioId);

      final productos = await listarProductos(db, categoriaId: almacen);
      expect(productos, hasLength(1));
      expect(productos.single.nombre, 'A');
    });

    // Bruno, 2026-09-19: "filtrar por productos sin proveedor, sin costo,
    // etcétera" desde la companion — pulido de catálogo.
    test('sinProveedor trae solo los que no tienen proveedor asignado', () async {
      final proveedorId = await crearProveedor(db, codigo: 'PRV1', nombre: 'Proveedor de prueba');
      await crearProducto(
        db,
        nombre: 'Con proveedor',
        proveedorId: proveedorId,
        precioCentavos: 1000,
        usuarioId: usuarioId,
      );
      await crearProducto(db, nombre: 'Sin proveedor', precioCentavos: 1000, usuarioId: usuarioId);

      final productos = await listarProductos(db, sinProveedor: true);
      expect(productos, hasLength(1));
      expect(productos.single.nombre, 'Sin proveedor');
    });

    test('sinCosto mira costoPorKiloCentavos en un pesable, costoCentavos en el resto', () async {
      await crearProducto(
        db,
        nombre: 'Con costo',
        precioCentavos: 1000,
        costoCentavos: 500,
        usuarioId: usuarioId,
      );
      await crearProducto(db, nombre: 'Sin costo', precioCentavos: 1000, usuarioId: usuarioId);
      await crearProducto(
        db,
        nombre: 'Pesable sin costo por kilo',
        esPesable: true,
        precioPorKiloCentavos: 5000,
        usuarioId: usuarioId,
      );
      await crearProducto(
        db,
        nombre: 'Pesable con costo por kilo',
        esPesable: true,
        precioPorKiloCentavos: 5000,
        costoPorKiloCentavos: 3000,
        usuarioId: usuarioId,
      );

      final productos = await listarProductos(db, sinCosto: true);
      expect(productos.map((p) => p.nombre), unorderedEquals(['Sin costo', 'Pesable sin costo por kilo']));
    });

    test('sinCategoria trae solo los que no tienen categoría asignada', () async {
      final almacen =
          (await (db.select(db.categorias)..where((c) => c.nombre.equals('Almacén'))).getSingle()).id;
      await crearProducto(db, nombre: 'Con categoría', categoriaId: almacen, precioCentavos: 1000, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'Sin categoría', precioCentavos: 1000, usuarioId: usuarioId);

      final productos = await listarProductos(db, sinCategoria: true);
      expect(productos, hasLength(1));
      expect(productos.single.nombre, 'Sin categoría');
    });

    test('sinCodigoBarras trae solo los que no tienen código cargado', () async {
      await crearProducto(
        db,
        nombre: 'Con código',
        codigoBarras: '7790001',
        precioCentavos: 1000,
        usuarioId: usuarioId,
      );
      await crearProducto(db, nombre: 'Sin código', precioCentavos: 1000, usuarioId: usuarioId);

      final productos = await listarProductos(db, sinCodigoBarras: true);
      expect(productos, hasLength(1));
      expect(productos.single.nombre, 'Sin código');
    });
  });

  group('productosSinCostoOrdenadosPorVenta', () {
    test('solo trae productos activos sin costo, ordenados por lo vendido', () async {
      final conCosto = await crearProducto(
        db,
        nombre: 'Con costo',
        precioCentavos: 1000,
        costoCentavos: 500,
        usuarioId: usuarioId,
      );
      final pocoVendido = await crearProducto(
        db,
        nombre: 'Sin costo, poco vendido',
        precioCentavos: 1000,
        usuarioId: usuarioId,
      );
      final muyVendido = await crearProducto(
        db,
        nombre: 'Sin costo, muy vendido',
        precioCentavos: 1000,
        usuarioId: usuarioId,
      );

      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );

      Future<void> venta(int productoId, int cantidad) async {
        final ventaId = await db.into(db.ventas).insert(
              VentasCompanion.insert(
                sesionCajaId: sesionId,
                usuarioId: usuarioId,
                subtotalCentavos: 1000 * cantidad,
                totalCentavos: 1000 * cantidad,
              ),
            );
        await db.into(db.lineasDeVenta).insert(
              LineasDeVentaCompanion.insert(
                ventaId: ventaId,
                productoId: Value(productoId),
                nombreProductoFoto: 'x',
                cantidad: Value(cantidad),
                precioUnitarioCentavos: 1000,
              ),
            );
      }

      await venta(conCosto, 100); // no debe aparecer: tiene costo
      await venta(pocoVendido, 1);
      await venta(muyVendido, 10);

      final resultado = await productosSinCostoOrdenadosPorVenta(db);

      expect(resultado.map((r) => r.producto.id), isNot(contains(conCosto)));
      expect(resultado, hasLength(2));
      expect(resultado.first.producto.id, muyVendido);
      expect(resultado.first.totalVendidoCentavos, 10000);
      expect(resultado.last.producto.id, pocoVendido);
    });
  });

  group('categorías', () {
    test('listarCategorias trae las 11 sembradas', () async {
      expect(await listarCategorias(db), hasLength(11));
    });

    test('crearCategoria agrega una nueva, escribiendo el nombre', () async {
      final id = await crearCategoria(db, 'Una categoría nueva');
      final categorias = await listarCategorias(db);
      expect(categorias.any((c) => c.id == id && c.nombre == 'Una categoría nueva'), true);
    });

    test('actualizarMarkupCategoria cambia solo el markup de esa categoría (fase 8)', () async {
      final id = await crearCategoria(db, 'Una categoría nueva');

      await actualizarMarkupCategoria(db, categoriaId: id, markupBp: 6000);

      final categoria = (await listarCategorias(db)).firstWhere((c) => c.id == id);
      expect(categoria.markupDefaultBp, 6000);
    });
  });

  group('productoAgotado', () {
    test('un producto de unidades en cero o negativo está agotado', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(productoAgotado(producto), true);
    });

    test('un producto de unidades en negativo también está agotado (Regla 8: informa, no bloquea)', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: -2, usuarioId: usuarioId);
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(productoAgotado(producto), true);
    });

    test('un producto de unidades con stock positivo no está agotado', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 3, usuarioId: usuarioId);
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(productoAgotado(producto), false);
    });

    test('un pesable mira stockGramos, no stock', () async {
      final id = await crearProducto(
        db,
        nombre: 'Jamón',
        esPesable: true,
        precioPorKiloCentavos: 8000000,
        stockGramos: 0,
        usuarioId: usuarioId,
      );
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(productoAgotado(producto), true);
    });

    test('un pesable con stockGramos null se considera agotado', () async {
      final id = await crearProducto(
        db,
        nombre: 'Jamón',
        esPesable: true,
        precioPorKiloCentavos: 8000000,
        usuarioId: usuarioId,
      );
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(productoAgotado(producto), true);
    });
  });

  group('ordenarAgotadosPrimero', () {
    test('pone los agotados o negativos antes que los que tienen stock', () async {
      final zapallo = await crearProducto(db, nombre: 'Zapallo', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
      final arroz = await crearProducto(db, nombre: 'Arroz', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);
      final banana = await crearProducto(db, nombre: 'Banana', precioCentavos: 1000, stock: -1, usuarioId: usuarioId);

      final productos = await listarProductos(db);
      final ordenados = ordenarAgotadosPrimero(productos);

      expect(ordenados.map((p) => p.id).toList(), [arroz, banana, zapallo]);
    });

    test('alfabético (ignorando acentos y mayúsculas) dentro de cada grupo', () async {
      final jamon = await crearProducto(db, nombre: 'Jamón', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);
      final azucar = await crearProducto(db, nombre: 'Azúcar', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);

      final productos = await listarProductos(db);
      final ordenados = ordenarAgotadosPrimero(productos);

      expect(ordenados.map((p) => p.id).toList(), [azucar, jamon]);
    });

    test('no modifica la lista original', () async {
      await crearProducto(db, nombre: 'A', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'B', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);

      final productos = await listarProductos(db);
      final ordenOriginal = productos.map((p) => p.id).toList();

      ordenarAgotadosPrimero(productos);

      expect(productos.map((p) => p.id).toList(), ordenOriginal);
    });
  });

  group('ajustarStockRapido — Regla 8', () {
    test('actualiza el stock en unidades y deja un movimiento AJUSTE', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);

      await ajustarStockRapido(db, productoId: id, usuarioId: usuarioId, stock: 6);

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.stock, 6);

      final movimiento =
          await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
      expect(movimiento.tipo, 'AJUSTE');
      expect(movimiento.stockAnterior, 10);
      expect(movimiento.stockPosterior, 6);
      expect(movimiento.usuarioId, usuarioId);
    });

    test('actualiza el stock en gramos de un pesable y deja el rastro correspondiente', () async {
      final id = await crearProducto(
        db,
        nombre: 'Jamón',
        esPesable: true,
        precioPorKiloCentavos: 8000000,
        stockGramos: 5000,
        usuarioId: usuarioId,
      );

      await ajustarStockRapido(db, productoId: id, usuarioId: usuarioId, stock: 0, stockGramos: 4300);

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.stockGramos, 4300);

      final movimiento =
          await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
      expect(movimiento.gramosAnterior, 5000);
      expect(movimiento.gramosPosterior, 4300);
    });

    test('no toca nombre, precio ni costo', () async {
      final id = await crearProducto(
        db,
        nombre: 'Fideos',
        precioCentavos: 1000,
        costoCentavos: 500,
        stock: 10,
        usuarioId: usuarioId,
      );

      await ajustarStockRapido(db, productoId: id, usuarioId: usuarioId, stock: 3, motivo: 'Conteo físico');

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.nombre, 'Fideos');
      expect(producto.precioCentavos, 1000);
      expect(producto.costoCentavos, 500);

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(1)); // sin cambio de precio/costo, sin foto nueva
    });

    test('el motivo se guarda en el movimiento', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);

      await ajustarStockRapido(db, productoId: id, usuarioId: usuarioId, stock: 8, motivo: 'Rotura / vencimiento');

      final movimiento =
          await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
      expect(movimiento.motivo, 'Rotura / vencimiento');
    });

    test('si el stock no cambió, no agrega movimiento', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);

      await ajustarStockRapido(db, productoId: id, usuarioId: usuarioId, stock: 10);

      final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();
      expect(movimientos, isEmpty);
    });
  });

  group('ajustarMontoEnLote — precio', () {
    test('sube el precio de varios productos por unidad a la vez, dejando el resto intacto', () async {
      final idCoca = await crearProducto(
        db,
        nombre: 'Coca-Cola 500ml',
        precioCentavos: 112000,
        costoCentavos: 80000,
        stock: 20,
        usuarioId: usuarioId,
      );
      final idSprite = await crearProducto(
        db,
        nombre: 'Sprite 500ml',
        precioCentavos: 108000,
        costoCentavos: 78000,
        stock: 15,
        usuarioId: usuarioId,
      );

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.precio,
        productoIds: [idCoca, idSprite],
        tipo: TipoAjustePrecio.sumarPorcentaje,
        valor: 1000, // 10%
        usuarioId: usuarioId,
      );

      final coca = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
      final sprite = await (db.select(db.productos)..where((p) => p.id.equals(idSprite))).getSingle();
      expect(coca.precioCentavos, 123200); // $1.120 + 10% = $1.232
      expect(sprite.precioCentavos, 118800); // $1.080 + 10% = $1.188
      // El costo no se toca — la edición masiva es de precio de venta.
      expect(coca.costoCentavos, 80000);
      expect(sprite.costoCentavos, 78000);
    });

    test('una selección mixta ajusta el campo correcto según esPesable', () async {
      final idUnidad = await crearProducto(
        db,
        nombre: 'Coca-Cola 500ml',
        precioCentavos: 100000,
        stock: 20,
        usuarioId: usuarioId,
      );
      final idPesable = await crearProducto(
        db,
        nombre: 'Queso cremoso',
        esPesable: true,
        precioPorKiloCentavos: 850000,
        stockGramos: 3200,
        usuarioId: usuarioId,
      );

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.precio,
        productoIds: [idUnidad, idPesable],
        tipo: TipoAjustePrecio.sumarMonto,
        valor: 20000, // $200
        usuarioId: usuarioId,
      );

      final unidad = await (db.select(db.productos)..where((p) => p.id.equals(idUnidad))).getSingle();
      final pesable = await (db.select(db.productos)..where((p) => p.id.equals(idPesable))).getSingle();
      expect(unidad.precioCentavos, 120000);
      expect(unidad.precioPorKiloCentavos, isNull);
      expect(pesable.precioPorKiloCentavos, 870000);
      expect(pesable.precioCentavos, isNull);
    });

    test('cada producto ajustado deja su propia foto en el historial de precios', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 100000, usuarioId: usuarioId);

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.precio,
        productoIds: [id],
        tipo: TipoAjustePrecio.nuevoFijo,
        valor: 150000,
        usuarioId: usuarioId,
      );

      final historial = await historialDelProducto(db, id);
      expect(historial, hasLength(2)); // alta + el ajuste masivo
      expect(historial.first.precioCentavos, 150000); // más reciente primero
    });

    test('no toca nombre, stock ni ningún otro campo del producto', () async {
      final id = await crearProducto(
        db,
        nombre: 'Fideos',
        precioCentavos: 100000,
        stock: 10,
        usuarioId: usuarioId,
      );

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.precio,
        productoIds: [id],
        tipo: TipoAjustePrecio.restarPorcentaje,
        valor: 500,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.nombre, 'Fideos');
      expect(producto.stock, 10);
    });
  });

  group('ajustarMontoEnLote — costo', () {
    test('sube el costo sin tocar el precio de venta', () async {
      final id = await crearProducto(
        db,
        nombre: 'Coca-Cola 500ml',
        precioCentavos: 150000,
        costoCentavos: 100000,
        usuarioId: usuarioId,
      );

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.costo,
        productoIds: [id],
        tipo: TipoAjustePrecio.sumarMonto,
        valor: 10000, // $100
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.costoCentavos, 110000);
      expect(producto.precioCentavos, 150000);
    });

    test('un pesable ajusta costoPorKilo, no costo por unidad', () async {
      final id = await crearProducto(
        db,
        nombre: 'Queso cremoso',
        esPesable: true,
        precioPorKiloCentavos: 850000,
        costoPorKiloCentavos: 600000,
        usuarioId: usuarioId,
      );

      await ajustarMontoEnLote(
        db,
        campo: CampoMonto.costo,
        productoIds: [id],
        tipo: TipoAjustePrecio.nuevoFijo,
        valor: 650000,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.costoPorKiloCentavos, 650000);
      expect(producto.costoCentavos, isNull);
    });
  });

  group('ajustarStockEnLote', () {
    test('suma unidades a varios productos, dejando un movimiento por cada uno', () async {
      final idCoca = await crearProducto(db, nombre: 'Coca-Cola 500ml', precioCentavos: 112000, stock: 20, usuarioId: usuarioId);
      final idSprite = await crearProducto(db, nombre: 'Sprite 500ml', precioCentavos: 108000, stock: 15, usuarioId: usuarioId);

      await ajustarStockEnLote(
        db,
        productoIds: [idCoca, idSprite],
        tipo: TipoAjusteStock.sumar,
        valor: 10,
        usuarioId: usuarioId,
      );

      final coca = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
      final sprite = await (db.select(db.productos)..where((p) => p.id.equals(idSprite))).getSingle();
      expect(coca.stock, 30);
      expect(sprite.stock, 25);

      final movimientoCoca =
          await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(idCoca))).getSingle();
      expect(movimientoCoca.stockAnterior, 20);
      expect(movimientoCoca.stockPosterior, 30);
      expect(movimientoCoca.motivo, 'Ajuste masivo');
    });

    test('un pesable ajusta stockGramos, no stock por unidad', () async {
      final id = await crearProducto(
        db,
        nombre: 'Queso cremoso',
        esPesable: true,
        precioPorKiloCentavos: 850000,
        stockGramos: 5000,
        usuarioId: usuarioId,
      );

      await ajustarStockEnLote(
        db,
        productoIds: [id],
        tipo: TipoAjusteStock.restar,
        valor: 1200,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.stockGramos, 3800);
      expect(producto.stock, 0);
    });

    test('nuevoFijo deja a todos en el mismo stock', () async {
      final id1 = await crearProducto(db, nombre: 'A', precioCentavos: 1000, stock: 3, usuarioId: usuarioId);
      final id2 = await crearProducto(db, nombre: 'B', precioCentavos: 1000, stock: 50, usuarioId: usuarioId);

      await ajustarStockEnLote(
        db,
        productoIds: [id1, id2],
        tipo: TipoAjusteStock.nuevoFijo,
        valor: 20,
        usuarioId: usuarioId,
      );

      final p1 = await (db.select(db.productos)..where((p) => p.id.equals(id1))).getSingle();
      final p2 = await (db.select(db.productos)..where((p) => p.id.equals(id2))).getSingle();
      expect(p1.stock, 20);
      expect(p2.stock, 20);
    });

    test('restar más de lo que hay da negativo, no se bloquea (Regla 8)', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);

      await ajustarStockEnLote(
        db,
        productoIds: [id],
        tipo: TipoAjusteStock.restar,
        valor: 10,
        usuarioId: usuarioId,
      );

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.stock, -5);
    });
  });

  group('asignarCategoriaEnLote', () {
    test('reasigna la categoría de varios productos a la vez', () async {
      final categoriaNueva = await crearCategoria(db, 'Fiambrería');
      final id1 = await crearProducto(db, nombre: 'Jamón cocido', usuarioId: usuarioId);
      final id2 = await crearProducto(db, nombre: 'Queso cremoso', usuarioId: usuarioId);

      await asignarCategoriaEnLote(
        db,
        productoIds: [id1, id2],
        categoriaId: categoriaNueva,
        usuarioId: usuarioId,
      );

      final p1 = await (db.select(db.productos)..where((p) => p.id.equals(id1))).getSingle();
      final p2 = await (db.select(db.productos)..where((p) => p.id.equals(id2))).getSingle();
      expect(p1.categoriaId, categoriaNueva);
      expect(p2.categoriaId, categoriaNueva);
    });

    test('null saca la categoría (queda "sin categoría")', () async {
      final categoria = await crearCategoria(db, 'Fiambrería');
      final id = await crearProducto(
        db,
        nombre: 'Jamón cocido',
        categoriaId: categoria,
        usuarioId: usuarioId,
      );

      await asignarCategoriaEnLote(db, productoIds: [id], categoriaId: null, usuarioId: usuarioId);

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.categoriaId, isNull);
    });
  });

  group('asignarProveedorEnLote', () {
    test('reasigna el proveedor de varios productos a la vez', () async {
      final proveedorId = await crearProveedor(db, nombre: 'Distribuidora nueva', codigo: 'DN');
      final id1 = await crearProducto(db, nombre: 'Coca-Cola 500ml', usuarioId: usuarioId);
      final id2 = await crearProducto(db, nombre: 'Sprite 500ml', usuarioId: usuarioId);

      await asignarProveedorEnLote(
        db,
        productoIds: [id1, id2],
        proveedorId: proveedorId,
        usuarioId: usuarioId,
      );

      final p1 = await (db.select(db.productos)..where((p) => p.id.equals(id1))).getSingle();
      final p2 = await (db.select(db.productos)..where((p) => p.id.equals(id2))).getSingle();
      expect(p1.proveedorId, proveedorId);
      expect(p2.proveedorId, proveedorId);
    });
  });

  group('cambiarActivoEnLote', () {
    test('desactiva varios productos a la vez, sin borrarlos', () async {
      final id1 = await crearProducto(db, nombre: 'Coca-Cola 500ml', usuarioId: usuarioId);
      final id2 = await crearProducto(db, nombre: 'Sprite 500ml', usuarioId: usuarioId);

      await cambiarActivoEnLote(db, productoIds: [id1, id2], activo: false);

      final p1 = await (db.select(db.productos)..where((p) => p.id.equals(id1))).getSingle();
      final p2 = await (db.select(db.productos)..where((p) => p.id.equals(id2))).getSingle();
      expect(p1.activo, false);
      expect(p2.activo, false);
    });

    test('reactiva varios productos a la vez', () async {
      final id = await crearProducto(db, nombre: 'Coca-Cola 500ml', usuarioId: usuarioId);
      await cambiarActivo(db, id: id, activo: false);

      await cambiarActivoEnLote(db, productoIds: [id], activo: true);

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(producto.activo, true);
    });
  });

  group('cargar un costo completa las ventas que quedaron sin costo (Bruno, 2026-09-26)', () {
    late int sesionId;

    setUp(() async {
      sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
    });

    Future<int> lineaVendida(int productoId, {int? costo, bool pesable = false}) async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 260000, totalCentavos: 260000),
          );
      return db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              productoId: Value(productoId),
              nombreProductoFoto: 'Coca Lata',
              esPesable: Value(pesable),
              gramos: Value(pesable ? 500 : null),
              cantidad: Value(pesable ? null : 1),
              precioUnitarioCentavos: 260000,
              costoUnitarioCentavos: Value(costo),
            ),
          );
    }

    Future<int?> costoDe(int lineaId) async =>
        (await (db.select(db.lineasDeVenta)..where((l) => l.id.equals(lineaId))).getSingle()).costoUnitarioCentavos;

    test('la venta sin costo toma el costo nuevo; la que ya tenía uno no se toca (costo-foto)', () async {
      final id = await crearProducto(db, nombre: 'Coca Lata', precioCentavos: 260000, usuarioId: usuarioId);
      final sinCosto = await lineaVendida(id);
      final conCosto = await lineaVendida(id, costo: 120000);

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Coca Lata',
        esPesable: false,
        precioCentavos: 260000,
        costoCentavos: 150000,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      expect(await costoDe(sinCosto), 150000);
      expect(await costoDe(conCosto), 120000);
    });

    test('una línea pesable toma el costo por kilo, no el unitario', () async {
      final id = await crearProducto(
        db,
        nombre: 'Queso',
        esPesable: true,
        precioPorKiloCentavos: 900000,
        usuarioId: usuarioId,
      );
      final linea = await lineaVendida(id, pesable: true);

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Queso',
        esPesable: true,
        precioPorKiloCentavos: 900000,
        costoPorKiloCentavos: 600000,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      expect(await costoDe(linea), 600000);
    });

    test('un costo \$0 no completa nada (cuenta como sin costo)', () async {
      final id = await crearProducto(db, nombre: 'Lillo suelto', precioCentavos: 20000, usuarioId: usuarioId);
      final linea = await lineaVendida(id);

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Lillo suelto',
        esPesable: false,
        precioCentavos: 20000,
        costoCentavos: 0,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      expect(await costoDe(linea), isNull);
    });

    test('guardar el producto sin costo no inventa uno', () async {
      final id = await crearProducto(db, nombre: 'Coca Lata', precioCentavos: 260000, usuarioId: usuarioId);
      final linea = await lineaVendida(id);

      await actualizarProducto(
        db,
        id: id,
        nombre: 'Coca Lata',
        esPesable: false,
        precioCentavos: 270000,
        stock: 0,
        activo: true,
        usuarioId: usuarioId,
      );

      expect(await costoDe(linea), isNull);
    });
  });
}
