// "Igualar la ganancia" de todo el catálogo (El dueño, 2026-10-16): todos con la misma ganancia sobre el precio, los
// proveedores al mismo %, los cigarrillos sin tocar y lo igualado sobrevive a un cambio de costo.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart' show crearProveedor;

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

  test('iguala a la centena, saca el precio fijo, pasa los proveedores al % y no toca cigarrillos, fiambres ni sin costo', () async {
    final prov = await crearProveedor(db, nombre: 'Distri', codigo: 'D1');
    final yerba = await crearProducto(db, nombre: 'Yerba', proveedorId: prov, precioCentavos: 120000, costoCentavos: 100000, usuarioId: usuario, precioFijo: true);
    final atado = await crearProducto(db, nombre: 'Atado', tipoCigarrillo: 'atado', precioCentavos: 500000, costoCentavos: 400000, usuarioId: usuario);
    final sinCosto = await crearProducto(db, nombre: 'Pan', precioCentavos: 90000, usuarioId: usuario);
    final jamon = await crearProducto(db, nombre: 'Jamón', esPesable: true, precioPorKiloCentavos: 1500000, costoPorKiloCentavos: 1000000, usuarioId: usuario);

    final cambiados = await igualarGananciaGeneral(db, gananciaBp: 3000, usuarioId: usuario);
    expect(cambiados, 1);

    final y = await producto(yerba);
    expect(y.precioCentavos, 150000); // $1.000 con 30 % = $1.428,57 → $1.500
    expect(y.precioFijo, isFalse);
    expect((await producto(atado)).precioCentavos, 500000);
    expect((await producto(sinCosto)).precioCentavos, 90000);
    expect((await producto(jamon)).precioPorKiloCentavos, 1500000);
    final p = await (db.select(db.proveedores)..where((t) => t.id.equals(prov))).getSingle();
    expect(p.markupBp, 3000);
  });
}
