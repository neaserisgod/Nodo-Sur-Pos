// Cobrar servicios (`REGLAS-NEGOCIO.md` §20, etapa 3): la línea guarda lo que costaron los insumos ese día, cobrar
// descuenta los insumos de la receta, anular o editar devuelven lo que la venta gastó, y "para reponer" suma lo usado.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;
  late int tintura;
  late int guantes;
  late Producto color;

  const configRecargo = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Lila'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;

    // Tintura: pomo de 60 ml a $6.000 → $100 el ml. Guantes: caja de 100 a $9.000 → $90 cada uno.
    tintura = await crearInsumo(db, nombre: 'Tintura', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 60000, costoEnvaseCentavos: 600000, usuarioId: usuarioId);
    await contarInsumo(db, insumoId: tintura, stockMilesimas: 120000, usuarioId: usuarioId);
    guantes = await crearInsumo(db, nombre: 'Guantes', unidad: UnidadInsumo.u, contenidoEnvaseMilesimas: 100000, costoEnvaseCentavos: 900000, usuarioId: usuarioId);
    await contarInsumo(db, insumoId: guantes, stockMilesimas: 10000, usuarioId: usuarioId);
    final id = await crearServicio(
      db,
      nombre: 'Color',
      precioCentavos: 3000000,
      duracionMinutos: 90,
      receta: [(insumoId: tintura, milesimas: 40000), (insumoId: guantes, milesimas: 2000)],
      sumaManoDeObra: true,
      usuarioId: usuarioId,
    );
    color = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
  });
  tearDown(() => db.close());

  Future<int> stockDe(int id) async => (await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()).stockMilesimas ?? 0;

  Venta ventaDe(int veces) => Venta(lineas: [lineaDesdeProducto(color, cantidad: veces)]);

  ResultadoTotalVenta totalDe(Venta v) => calcularTotalVenta(
        venta: v,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

  Future<int> cobrar(int veces) async {
    final venta = ventaDe(veces);
    final r = totalDe(venta);
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

  test('cobrar descuenta los insumos de la receta y deja su movimiento atado a la venta', () async {
    final ventaId = await cobrar(1);
    expect(await stockDe(tintura), 80000);
    expect(await stockDe(guantes), 8000);
    final movs = await (db.select(db.movimientosDeStock)..where((m) => m.ventaId.equals(ventaId))).get();
    expect(movs, hasLength(2));
    expect(movs.every((m) => m.tipo == 'VENTA' && m.motivo == 'Color'), isTrue);
    expect((await (db.select(db.productos)..where((p) => p.id.equals(color.id))).getSingle()).stock, 0, reason: 'el servicio no tiene stock');
  });

  test('la línea guarda el costo de los insumos de ese día, sin mano de obra', () async {
    final ventaId = await cobrar(2);
    final linea = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).getSingle();
    // 40 ml × $100 + 2 guantes × $90 = $4.180.
    expect(linea.costoUnitarioCentavos, 418000);
    expect(linea.cantidad, 2);

    // Sube la tintura: la venta ya hecha no cambia (Regla 4).
    await cargarCompraDeInsumo(db, insumoId: tintura, envases: 1, costoEnvaseCentavos: 900000, usuarioId: usuarioId);
    final igual = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).getSingle();
    expect(igual.costoUnitarioCentavos, 418000);
  });

  test('si falta un insumo, cobra igual y el stock queda en negativo (por defecto solo avisa)', () async {
    await contarInsumo(db, insumoId: guantes, stockMilesimas: 1000, usuarioId: usuarioId);
    await cobrar(1);
    expect(await stockDe(guantes), -1000);
  });

  test('anular devuelve lo que la venta gastó, aunque la receta haya cambiado después', () async {
    final ventaId = await cobrar(1);
    await editarServicio(db, id: color.id, nombre: 'Color', precioCentavos: 3000000, duracionMinutos: 90,
        receta: [(insumoId: tintura, milesimas: 70000)], usuarioId: usuarioId);
    await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'Se equivocó de servicio');
    expect(await stockDe(tintura), 120000);
    expect(await stockDe(guantes), 10000);
  });

  test('editar devuelve lo gastado y vuelve a descontar lo nuevo: el neto queda justo', () async {
    final ventaId = await cobrar(1);
    final nueva = ventaDe(3);
    final r = totalDe(nueva);
    await editarVenta(
      db,
      ventaId: ventaId,
      ventaNueva: nueva,
      resultadoNuevo: r,
      pagosNuevos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: r.totalCentavos, esEfectivo: true)],
      usuarioId: usuarioId,
      motivo: 'Eran tres',
    );
    expect(await stockDe(tintura), 0);
    expect(await stockDe(guantes), 4000);
    // Anular después de editar devuelve todo, una sola vez.
    await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'No vino nadie');
    expect(await stockDe(tintura), 120000);
    expect(await stockDe(guantes), 10000);
  });

  test('para reponer insumos suma lo que costó lo usado en la caja, sin las anuladas', () async {
    await cobrar(1);
    final anulada = await cobrar(1);
    await anularVenta(db, ventaId: anulada, usuarioId: usuarioId, motivo: 'error');
    await cobrar(2);
    expect(await paraReponerInsumosCentavos(db, sesionCajaId: sesionId), 418000 * 3);
  });

  test('la ganancia de la línea es precio menos insumos (la mano de obra no entra)', () async {
    final ventaId = await cobrar(1);
    final linea = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).getSingle();
    expect(linea.precioUnitarioCentavos - linea.costoUnitarioCentavos!, 3000000 - 418000);
  });
}
