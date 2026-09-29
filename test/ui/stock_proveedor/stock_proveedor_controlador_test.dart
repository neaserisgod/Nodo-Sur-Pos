import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/ui/stock_proveedor/stock_proveedor_controlador.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  });
  tearDown(() => db.close());

  test('cargarTodo trae categorías, proveedores y la lista con agotados primero', () async {
    await crearProducto(db, nombre: 'Con stock', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
    await crearProducto(db, nombre: 'Agotado', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);

    final c = StockProveedorControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    expect(c.categorias, hasLength(11));
    expect(c.proveedores, hasLength(15));
    expect(c.productos.first.nombre, 'Agotado');
    expect(c.cargando, false);
  });

  test('motivo por default es el primero de la lista de motivos', () async {
    final c = StockProveedorControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    expect(c.motivo, motivosAjusteDeStock.first);
  });

  test('elegirMotivo cambia el motivo usado en el próximo ajuste', () async {
    final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);
    final c = StockProveedorControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    c.elegirMotivo('Rotura / vencimiento');
    final producto = c.productos.firstWhere((p) => p.id == id);
    await c.ajustarStock(producto, stock: 6);

    final movimiento =
        await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
    expect(movimiento.motivo, 'Rotura / vencimiento');
  });

  test('ajustarStock actualiza el stock, deja rastro y recarga la lista ordenada', () async {
    final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 10, usuarioId: usuarioId);
    final c = StockProveedorControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    final producto = c.productos.firstWhere((p) => p.id == id);
    await c.ajustarStock(producto, stock: 0);

    expect(c.productos.firstWhere((p) => p.id == id).stock, 0);
    // pasó a agotado: queda primero en la lista recargada.
    expect(c.productos.first.id, id);

    final movimiento =
        await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).getSingle();
    expect(movimiento.tipo, 'AJUSTE');
    expect(movimiento.stockPosterior, 0);
  });

  group('filtros', () {
    test('filtrarPorProveedor deja solo los de ese proveedor', () async {
      final proveedores = await listarProveedores(db);
      final serra = proveedores.firstWhere((p) => p.codigo == 'S');
      final wesley = proveedores.firstWhere((p) => p.codigo == 'W');

      await crearProducto(db, nombre: 'De Serra', proveedorId: serra.id, precioCentavos: 1000, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'De Wesley', proveedorId: wesley.id, precioCentavos: 1000, usuarioId: usuarioId);

      final c = StockProveedorControlador(db, usuarioId: usuarioId);
      await c.cargarTodo();

      await c.filtrarPorProveedor(serra.id);

      expect(c.productos, hasLength(1));
      expect(c.productos.single.nombre, 'De Serra');
    });

    test('filtrarPorCategoria deja solo los de esa categoría', () async {
      final categorias = await listarCategorias(db);
      final almacen = categorias.firstWhere((c) => c.nombre == 'Almacén');
      final bebidas = categorias.firstWhere((c) => c.nombre == 'Bebidas');

      await crearProducto(db, nombre: 'A', categoriaId: almacen.id, precioCentavos: 1000, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'B', categoriaId: bebidas.id, precioCentavos: 1000, usuarioId: usuarioId);

      final c = StockProveedorControlador(db, usuarioId: usuarioId);
      await c.cargarTodo();

      await c.filtrarPorCategoria(almacen.id);

      expect(c.productos, hasLength(1));
      expect(c.productos.single.nombre, 'A');
    });
  });

  group('conteo', () {
    test('contar no toca la base; aplicarAjustes aplica solo los que difieren', () async {
      final fideos = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, costoCentavos: 60000, stock: 10, usuarioId: usuarioId);
      final yerba = await crearProducto(db, nombre: 'Yerba', precioCentavos: 1000, stock: 4, usuarioId: usuarioId);
      final c = StockProveedorControlador(db, usuarioId: usuarioId);
      await c.cargarTodo();
      final pFideos = c.productos.firstWhere((p) => p.id == fideos);
      final pYerba = c.productos.firstWhere((p) => p.id == yerba);

      c.contar(pFideos, 7);
      c.sumar(pYerba, 0); // contado igual al sistema: "Justo"

      expect(c.diferencia(pFideos), -3);
      expect(c.diferencia(pYerba), 0);
      expect(c.conDiferencia.map((p) => p.id), [fideos]);
      expect(c.unidadesFaltantes, 3);
      expect(c.costoFaltanteCentavos, 180000);
      expect((await (db.select(db.productos)..where((p) => p.id.equals(fideos))).getSingle()).stock, 10);

      expect(await c.aplicarAjustes(), 1);

      expect((await (db.select(db.productos)..where((p) => p.id.equals(fideos))).getSingle()).stock, 7);
      final movimientos = await db.select(db.movimientosDeStock).get();
      expect(movimientos.map((m) => m.productoId), [fideos]);
      expect(movimientos.single.motivo, motivosAjusteDeStock.first);
      expect(c.contados, isEmpty);
    });

    test('sumar arranca desde el sistema y no baja de cero', () async {
      final id = await crearProducto(db, nombre: 'Fideos', precioCentavos: 1000, stock: 1, usuarioId: usuarioId);
      final c = StockProveedorControlador(db, usuarioId: usuarioId);
      await c.cargarTodo();
      final p = c.productos.firstWhere((p) => p.id == id);

      c.sumar(p, 1);
      expect(c.contado(p), 2);
      c.sumar(p, -1);
      c.sumar(p, -1);
      c.sumar(p, -1);
      expect(c.contado(p), 0);
    });

    test('filtros "sin contar" y "con diferencia"', () async {
      final a = await crearProducto(db, nombre: 'A', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
      await crearProducto(db, nombre: 'B', precioCentavos: 1000, stock: 5, usuarioId: usuarioId);
      final c = StockProveedorControlador(db, usuarioId: usuarioId);
      await c.cargarTodo();
      c.contar(c.productos.firstWhere((p) => p.id == a), 4);

      c.elegirFiltro(FiltroConteo.sinContar);
      expect(c.visibles.map((p) => p.nombre), ['B']);
      c.elegirFiltro(FiltroConteo.conDiferencia);
      expect(c.visibles.map((p) => p.nombre), ['A']);
    });
  });
}
