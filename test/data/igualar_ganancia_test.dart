// Precios de todo contra una base real (El dueño, 2026-10-16): subir sobre el costo, igualar el markup y deshacer la suba.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart' show crearProveedor;
import 'package:la_plazoleta/domain/edicion_masiva_precios.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
  });
  tearDown(() => db.close());

  Future<Producto> producto(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  test('igualar el markup: a la centena, saca el precio fijo, pasa los proveedores y no toca cigarrillos, fiambres ni sin costo', () async {
    final prov = await crearProveedor(db, nombre: 'Distri', codigo: 'D1');
    final yerba = await crearProducto(db, nombre: 'Yerba', proveedorId: prov, precioCentavos: 120000, costoCentavos: 100000, usuarioId: usuario, precioFijo: true);
    final atado = await crearProducto(db, nombre: 'Atado', tipoCigarrillo: 'atado', precioCentavos: 500000, costoCentavos: 400000, usuarioId: usuario);
    final sinCosto = await crearProducto(db, nombre: 'Pan', precioCentavos: 90000, usuarioId: usuario);
    final jamon = await crearProducto(db, nombre: 'Jamón', esPesable: true, precioPorKiloCentavos: 1500000, costoPorKiloCentavos: 1000000, usuarioId: usuario);

    expect(await igualarMarkupGeneral(db, markupBp: 7000, usuarioId: usuario), 1);

    final y = await producto(yerba);
    expect(y.precioCentavos, 170000);
    expect(y.precioFijo, isFalse);
    expect((await producto(atado)).precioCentavos, 500000);
    expect((await producto(sinCosto)).precioCentavos, 90000);
    expect((await producto(jamon)).precioPorKiloCentavos, 1500000);
    final p = await (db.select(db.proveedores)..where((t) => t.id.equals(prov))).getSingle();
    expect(p.markupBp, 4117);
  });

  test('deshacer la suba del 15 % sobre el precio y subir 15 % sobre el costo: \$7.000 → \$7.900', () async {
    final ids = [
      for (var i = 0; i < 6; i++) await crearProducto(db, nombre: 'P$i', precioCentavos: 700000, costoCentavos: 600000, usuarioId: usuario),
    ];
    // Los productos se dieron de alta antes (en la vida real no caen en el mismo minuto que la suba).
    await db.update(db.historialDePrecios).write(HistorialDePreciosCompanion(fecha: Value(DateTime.now().subtract(const Duration(days: 1)))));
    // Lo que pasó: la primera versión subió 15 % sobre el precio.
    await ajustarMontoEnLote(db, productoIds: ids, campo: CampoMonto.precio, tipo: TipoAjustePrecio.sumarPorcentaje, valor: 1500, usuarioId: usuario);
    expect((await producto(ids.first)).precioCentavos, 805000);

    final cuenta = await deshacerUltimaSuba(db, usuarioId: usuario, soloContar: true);
    expect(cuenta.productos, 6);
    expect((await producto(ids.first)).precioCentavos, 805000); // contar no cambia nada

    // Uno se corrigió a mano después de la suba: ese no se toca.
    final p5 = await producto(ids.last);
    await actualizarProducto(db, id: p5.id, nombre: p5.nombre, codigoBarras: null, categoriaId: null, proveedorId: null, esPesable: false,
        tipoCigarrillo: 'ninguno', precioCentavos: 750000, costoCentavos: 600000, precioPorKiloCentavos: null, costoPorKiloCentavos: null,
        stock: 0, stockGramos: null, activo: true, usuarioId: usuario);

    expect((await deshacerUltimaSuba(db, usuarioId: usuario)).productos, 5);
    expect((await producto(ids.first)).precioCentavos, 700000);
    expect((await producto(ids.last)).precioCentavos, 750000);

    // "Subir todo" es la edición en lote con el % sobre el costo.
    await ajustarMontoEnLote(db, productoIds: ids, campo: CampoMonto.precio, tipo: TipoAjustePrecio.sumarPorcentajeDelCosto, valor: 1500, usuarioId: usuario);
    expect((await producto(ids.first)).precioCentavos, 790000);
  });
}
