import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  });
  tearDown(() => db.close());

  test('cargarCostoProducto carga el costo, deja todo lo demás y completa las ventas sin costo', () async {
    final id = await crearProducto(db, nombre: 'Bolsa de hielo', precioCentavos: 250000, stock: 8, usuarioId: usuarioId);
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final efectivo = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    final venta = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 2)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: efectivo, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );
    final inicio = DateTime.now().subtract(const Duration(hours: 1));
    final antes = await vendidoSinCostoDesde(db, inicio);
    expect(antes.single.productoId, id);

    await cargarCostoProducto(db, productoId: id, costoCentavos: 150000, usuarioId: usuarioId);

    final despues = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(despues.costoCentavos, 150000);
    expect(despues.precioCentavos, 250000);
    expect(despues.stock, 6); // la venta ya lo había bajado: no se toca
    expect(await vendidoSinCostoDesde(db, inicio), isEmpty);
  });
}
