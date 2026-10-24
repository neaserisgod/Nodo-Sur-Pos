// Vender en un local gastronómico pasa por la cocina como un pedido (El dueño, 2026-10-24: "vender es como si se tomara un
// pedido"): una venta con un plato deja un pedido de mostrador ya cobrado y "por hacer", en la misma transacción.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/servicios/comandera_point.dart' show datosComandaDe;

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesion;
  late int empanada;
  late int coca;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    empanada = await crearServicio(db, nombre: 'Empanada', precioCentavos: 150000, duracionMinutos: 5, usuarioId: usuarioId);
    coca = await crearProductoDeVenta(db, nombre: 'Coca-Cola 1,5 L', precioCentavos: 380000, costoCentavos: 240000, stockInicial: 4, usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  Future<LineaVenta> linea(int id, {int cantidad = 1}) async {
    final p = await (db.select(db.productos)..where((x) => x.id.equals(id))).getSingle();
    final l = lineaDesdeProducto(p) as LineaVentaPorUnidad;
    return LineaVentaPorUnidad(
      productoId: l.productoId,
      nombreProducto: l.nombreProducto,
      proveedorId: l.proveedorId,
      cantidad: cantidad,
      precioUnitarioCentavos: l.precioUnitarioCentavos,
      costoUnitarioCentavos: l.costoUnitarioCentavos,
    );
  }

  Future<int> vender(List<LineaVenta> lineas, {String? pedidoDeMostrador = '', int? pedidoId}) async => (await registrarVentaSegunMedio(db,
          lineas: lineas,
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesion,
          usuarioId: usuarioId,
          pedidoId: pedidoId,
          pedidoDeMostrador: pedidoDeMostrador))
      .ventaId;

  test('una venta con un plato deja un pedido de mostrador, cobrado y por hacer, con todo lo vendido', () async {
    final ventaId = await vender([await linea(empanada, cantidad: 6), await linea(coca)]);
    final p = (await pedidosAbiertos(db)).single;
    expect(p.ventaId, ventaId);
    expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porHacer, reason: 'así sale la comanda');
    expect(CanalPedido.desdeClave(p.canal), CanalPedido.mostrador);
    expect(FormaEntrega.desdeClave(p.formaEntrega), FormaEntrega.retiro);
    expect(p.nombreCliente, 'Mostrador');
    expect(datosComandaDe(p).pagado, isTrue, reason: 'la comanda no dice "A COBRAR" lo que ya se cobró');
    final lineas = lineasDe(p);
    expect([for (final l in lineas) (l.nombre, l.cantidad, l.precioCentavos)], [('Empanada', 6, 150000), ('Coca-Cola 1,5 L', 1, 380000)]);
  });

  test('ya cobrado: al estar listo se entrega, sin volver a cobrarlo', () async {
    await vender([await linea(empanada)]);
    final p = (await pedidosAbiertos(db)).single;
    await avanzarPedido(db, p.id, EstadoPedido.listo);
    await avanzarPedido(db, p.id, EstadoPedido.entregado);
    expect(await pedidosAbiertos(db), isEmpty);
    await expectLater(marcarPedidoCobrado(db, p.id, ventaId: 1), throwsA(isA<PedidoYaCobrado>()));
  });

  test('solo bebidas no arma pedido: no hay nada que cocinar', () async {
    await vender([await linea(coca, cantidad: 2)]);
    expect(await db.select(db.pedidosGastronomia).get(), isEmpty);
  });

  test('un combo con un plato también va a la cocina', () async {
    final combo = await guardarPromo(db,
        nombre: 'Media docena y Coca',
        articulos: [(productoId: empanada, cantidad: 6), (productoId: coca, cantidad: 1)],
        gananciaBp: 0,
        precioAManoCentavos: 1200000,
        usuarioId: usuarioId);
    await vender([await linea(combo)]);
    expect(lineasDe((await pedidosAbiertos(db)).single).single.nombre, 'Media docena y Coca');
  });

  test('aunque el local no tenga prendido el retiro: el cliente está en el mostrador', () async {
    await guardarConfigPedidos(db, const ConfigPedidos(retiro: false, cadetePropio: true));
    await vender([await linea(empanada)]);
    expect(FormaEntrega.desdeClave((await pedidosAbiertos(db)).single.formaEntrega), FormaEntrega.retiro);
  });

  test('cobrar un pedido que ya existe no arma otro, y una venta común (sin pedido de mostrador) tampoco', () async {
    final e = await (db.select(db.productos)..where((x) => x.id.equals(empanada))).getSingle();
    final id = await crearPedido(db,
        canal: CanalPedido.telefono,
        nombreCliente: 'Juan',
        lineas: [LineaPedido(gid: e.globalId!, nombre: e.nombre, cantidad: 1, precioCentavos: 150000)],
        usuarioId: usuarioId);
    await vender(await lineasDeVentaDePedido(db, (await pedidosAbiertos(db)).single), pedidoId: id);
    await vender([await linea(empanada)], pedidoDeMostrador: null);
    expect(await db.select(db.pedidosGastronomia).get(), hasLength(1));
  });
}
