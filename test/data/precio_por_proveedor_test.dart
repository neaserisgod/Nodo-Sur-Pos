import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/domain/edicion_masiva_precios.dart';
import '../helpers/base_para_tests.dart';

/// Precio automático por proveedor (Bruno, 2026-09-29): porcentaje sobre el
/// costo + redondeo a la próxima centena; los cigarrillos quedan como están.
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int proveedorId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    proveedorId = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'ZP', nombre: 'Prov test'));
  });
  tearDown(() => db.close());

  Future<int> producto(
    String nombre, {
    int? costo,
    int? precio,
    String tipoCigarrillo = 'ninguno',
    bool esPesable = false,
    bool precioFijo = false,
    int? conProveedor,
  }) {
    return db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: nombre,
            proveedorId: Value(conProveedor ?? proveedorId),
            tipoCigarrillo: Value(tipoCigarrillo),
            esPesable: Value(esPesable),
            precioFijo: Value(precioFijo),
            costoCentavos: Value(esPesable ? null : costo),
            precioCentavos: Value(esPesable ? null : precio),
            costoPorKiloCentavos: Value(esPesable ? costo : null),
            precioPorKiloCentavos: Value(esPesable ? precio : null),
          ),
        );
  }

  Future<Producto> leer(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  test('aplicar el porcentaje recalcula los precios con costo y redondea a la centena', () async {
    final a = await producto('A', costo: 103000, precio: 150000); // 1.030 → 1.339 → 1.400
    final b = await producto('B', costo: 100000, precio: 999900); // 1.000 → 1.300
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);

    final n = await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId);
    expect(n, 2);
    expect((await leer(a)).precioCentavos, 140000);
    expect((await leer(b)).precioCentavos, 130000);
  });

  test('los cigarrillos quedan como están, aunque tengan costo y el proveedor tenga porcentaje', () async {
    final atado = await producto('Marlboro', costo: 400000, precio: 500000, tipoCigarrillo: 'atado');
    final suelto = await producto('Suelto', costo: 10000, precio: 30000, tipoCigarrillo: 'suelto');
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 5000);

    await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId);
    expect((await leer(atado)).precioCentavos, 500000);
    expect((await leer(suelto)).precioCentavos, 30000);
  });

  test('un producto con precio fijo, o sin costo, no se toca', () async {
    final fijo = await producto('Fijo', costo: 100000, precio: 777700, precioFijo: true);
    final sinCosto = await producto('Sin costo', precio: 123400);
    final ceroCosto = await producto('Costo cero', costo: 0, precio: 55500);
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);

    final n = await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId);
    expect(n, 0);
    expect((await leer(fijo)).precioCentavos, 777700);
    expect((await leer(sinCosto)).precioCentavos, 123400);
    expect((await leer(ceroCosto)).precioCentavos, 55500);
  });

  test('un proveedor sin porcentaje no cambia nada; los productos de otro proveedor tampoco', () async {
    final otro = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'ZQ', nombre: 'Otro'));
    final mio = await producto('Mío', costo: 100000, precio: 111100);
    final ajeno = await producto('Ajeno', costo: 100000, precio: 222200, conProveedor: otro);

    expect(await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId), 0);

    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);
    await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId);
    expect((await leer(mio)).precioCentavos, 130000);
    expect((await leer(ajeno)).precioCentavos, 222200);
  });

  test('un pesable usa costo y precio por kilo', () async {
    final queso = await producto('Queso', costo: 600000, precio: 700000, esPesable: true); // 6.000 * 1,5 = 9.000
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 5000);

    await aplicarPorcentajeDeProveedor(db, proveedorId: proveedorId, usuarioId: usuarioId);
    expect((await leer(queso)).precioPorKiloCentavos, 900000);
  });

  test('cambiar el costo de un producto recalcula su precio solo (y deja historial)', () async {
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);
    final id = await producto('A', costo: 100000, precio: 130000);
    final p = await leer(id);

    await actualizarProducto(
      db,
      id: id,
      nombre: p.nombre,
      esPesable: false,
      proveedorId: proveedorId,
      precioCentavos: p.precioCentavos,
      costoCentavos: 120000, // subió el costo; el precio no se tocó a mano
      stock: p.stock,
      activo: true,
      usuarioId: usuarioId,
    );
    expect((await leer(id)).precioCentavos, 160000); // 1.200 * 1,3 = 1.560 → 1.600
    expect(await historialDelProducto(db, id), isNotEmpty);
  });

  test('con precio fijo, cambiar el costo no mueve el precio', () async {
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);
    final id = await producto('A', costo: 100000, precio: 130000, precioFijo: true);
    final p = await leer(id);

    await actualizarProducto(
      db,
      id: id,
      nombre: p.nombre,
      esPesable: false,
      proveedorId: proveedorId,
      precioCentavos: p.precioCentavos,
      costoCentavos: 120000,
      stock: p.stock,
      activo: true,
      usuarioId: usuarioId,
    );
    expect((await leer(id)).precioCentavos, 130000);
  });

  test('ajustar el precio a mano en lote lo deja fijo', () async {
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);
    final id = await producto('A', costo: 100000, precio: 130000);
    await ajustarMontoEnLote(
      db,
      productoIds: [id],
      campo: CampoMonto.precio,
      tipo: TipoAjustePrecio.sumarMonto,
      valor: 10000,
      usuarioId: usuarioId,
    );
    final p = await leer(id);
    expect(p.precioCentavos, 140000);
    expect(p.precioFijo, true);
  });

  test('la vista previa lista solo lo que cambiaría', () async {
    await producto('Ya está', costo: 100000, precio: 130000);
    await producto('Cambia', costo: 100000, precio: 100000);
    await guardarPorcentajeProveedor(db, proveedorId: proveedorId, markupBp: 3000);

    final cambios = await cambiosPorPorcentaje(db, proveedorId);
    expect(cambios.map((c) => c.producto.nombre), ['Cambia']);
    expect(cambios.single.precioNuevoCentavos, 130000);
  });
}
