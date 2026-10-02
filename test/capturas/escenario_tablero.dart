// Base de test con ventas de hoy (efectivo y Mercado Pago) de productos que
// tienen proveedor, para probar el tablero del día y compararlo con
// Separaciones. Tampoco estaba en el repositorio: `repositorio_tablero_test`
// no cargaba por eso.
import 'package:drift/drift.dart' show Value;
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

Future<AppDatabase> crearEscenarioTablero() async {
  final db = baseDeTest();
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
  final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 3000000);
  final proveedorId = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'TB', nombre: 'Distribuidora tablero'));

  for (final p in [
    ('Cerveza lata 473 ml', 210000, 150000, 48),
    ('Gaseosa cola 2,25 L', 290000, 200000, 4),
    ('Yerba 1 kg', 460000, 310000, 20),
    ('Alfajor triple', 120000, 70000, 60),
  ]) {
    await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: p.$1,
            precioCentavos: Value(p.$2),
            costoCentavos: Value(p.$3),
            stock: Value(p.$4),
            proveedorId: Value(proveedorId),
          ),
        );
  }

  final medios = await db.select(db.mediosDePago).get();
  final efectivo = medios.firstWhere((m) => m.esEfectivo);
  final virtual = medios.firstWhere((m) => !m.esEfectivo);
  final productos = (await db.select(db.productos).get()).where((p) => p.precioCentavos != null && !p.esPesable).toList();

  Future<void> vender(List<(int, int)> items, {required bool conEfectivo}) async {
    final venta = Venta(lineas: [for (final (i, cant) in items) lineaDesdeProducto(productos[i], cantidad: cant)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: conEfectivo ? ComposicionPago.efectivo : ComposicionPago.virtual,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    final medio = conEfectivo ? efectivo : virtual;
    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medio.id, montoCentavos: resultado.totalCentavos, esEfectivo: conEfectivo)],
    );
  }

  await vender([(0, 2), (1, 1)], conEfectivo: true);
  await vender([(2, 1), (3, 3)], conEfectivo: false);
  await vender([(0, 4)], conEfectivo: true);
  await vender([(1, 2), (2, 1)], conEfectivo: false);
  return db;
}
