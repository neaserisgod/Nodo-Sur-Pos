// Combos de Nodo Gastro (El dueño, 2026-10-23: "pollo + papas + Coca"): una promo puede llevar platos. El costo del plato es
// el de sus insumos de hoy, el plato no limita cuántos combos alcanzan, y al cobrarlo se gastan sus insumos (anular los
// devuelve), como cuando se vende suelto.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/promo.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;
  late int pollo;
  late int plato;
  late int coca;
  late int sinReceta;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;

    // Pollo: 1 kg a $8.000 → el plato usa 1 kg y cuesta $8.000.
    pollo = await crearInsumo(db, nombre: 'Pollo', unidad: UnidadInsumo.g, contenidoEnvaseMilesimas: 1000000, costoEnvaseCentavos: 800000, usuarioId: usuarioId);
    await contarInsumo(db, insumoId: pollo, stockMilesimas: 5000000, usuarioId: usuarioId);
    plato = await crearServicio(db, nombre: 'Pollo al spiedo', precioCentavos: 1400000, duracionMinutos: 15, receta: [(insumoId: pollo, milesimas: 1000000)], usuarioId: usuarioId);
    sinReceta = await crearServicio(db, nombre: 'Empanada', precioCentavos: 150000, duracionMinutos: 5, usuarioId: usuarioId);
    coca = await crearProductoDeVenta(db, nombre: 'Coca-Cola 1,5 L', precioCentavos: 380000, costoCentavos: 240000, stockInicial: 4, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  Future<Producto> producto(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  Future<int> armarCombo() => guardarPromo(
        db,
        nombre: 'Combo pollo',
        articulos: [(productoId: plato, cantidad: 1), (productoId: coca, cantidad: 1)],
        gananciaBp: 3000,
        usuarioId: usuarioId,
      );

  Future<int> cobrar(Producto promo) async {
    final venta = Venta(lineas: [lineaDesdeProducto(promo)]);
    final r = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 0, atadoAdicionalCentavos: 0),
      pasoRedondeoCentavos: 0,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: r,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: r.totalCentavos, esEfectivo: true)],
    );
    return ventaId;
  }

  test('un plato con insumos entra en el combo, con el costo de su receta; uno sin receta no (no hay con qué calcular)', () async {
    final elegibles = {for (final p in await productosParaPromo(db)) p.id: p};
    expect(elegibles[plato]?.costoCentavos, 800000);
    expect(elegibles.containsKey(coca), isTrue);
    expect(elegibles.containsKey(sinReceta), isFalse);
    expect(elegibles.containsKey(pollo), isFalse, reason: 'un insumo no se vende');
  });

  test('el combo cuesta plato + bebida y lo que alcanza lo pone la bebida', () async {
    await armarCombo();
    final combo = (await listarPromos(db)).single;
    expect(combo.costoCentavos, 800000 + 240000);
    expect(combo.stock, 4);
  });

  test('cobrar el combo gasta los insumos del plato y una bebida; anularlo los devuelve', () async {
    final promo = await producto(await armarCombo());
    final ventaId = await cobrar(promo);

    expect((await producto(pollo)).stockMilesimas, 4000000);
    expect((await producto(coca)).stock, 3);
    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    final delPlato = lineas.singleWhere((l) => l.productoId == plato);
    expect(delPlato.costoUnitarioCentavos, 800000, reason: 'costo-foto: los insumos de hoy');
    expect(lineas.fold<int>(0, (a, l) => a + l.precioUnitarioCentavos * (l.cantidad ?? 1)), promo.precioCentavos);

    await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'error');
    expect((await producto(pollo)).stockMilesimas, 5000000);
    expect((await producto(coca)).stock, 4);
  });

  test('un combo solo de platos no tiene tope', () async {
    final otro = await crearServicio(db, nombre: 'Papas', precioCentavos: 600000, duracionMinutos: 10, receta: [(insumoId: pollo, milesimas: 100000)], usuarioId: usuarioId);
    await guardarPromo(db, nombre: 'Pollo con papas', articulos: [(productoId: plato, cantidad: 1), (productoId: otro, cantidad: 1)], gananciaBp: 3000, usuarioId: usuarioId);
    expect((await listarPromos(db)).single.stock, stockPromoSinTope);
    final catalogo = await catalogoConStockDePromos(db);
    expect(catalogo.singleWhere((p) => p.esPromo).stock, stockPromoSinTope);
  });
}
