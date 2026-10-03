// Encargues = mercadería que YA está en el local y se aparta para un cliente (El dueño, 2026-10-02). Apartar saca el
// stock en el momento, con rastro; cancelar lo devuelve; entregar es una venta normal que libera lo apartado en la
// misma transacción, así el stock final es el de haber vendido, ni uno más ni uno menos.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_encargues.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int galletitas;
  late int queso;

  Future<Producto> producto(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    galletitas = await crearProducto(db, nombre: 'Galletitas', precioCentavos: 150000, costoCentavos: 90000, stock: 10, usuarioId: usuarioId);
    queso = await crearProducto(
      db,
      nombre: 'Queso barra',
      esPesable: true,
      precioPorKiloCentavos: 1000000,
      costoPorKiloCentavos: 600000,
      stockGramos: 5000,
      usuarioId: usuarioId,
    );
  });
  tearDown(() => db.close());

  test('apartar saca el stock ya, deja un movimiento con el nombre del cliente y el encargue queda pendiente', () async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3), LineaEncargueNueva(productoId: queso, gramos: 250)],
      usuarioId: usuarioId,
    );

    expect((await producto(galletitas)).stock, 7);
    expect((await producto(queso)).stockGramos, 4750);
    final movs = await (db.select(db.movimientosDeStock)..where((m) => m.tipo.equals('AJUSTE'))).get();
    expect(movs.where((m) => m.motivo == 'Apartado para María'), hasLength(2));

    final lista = await listarEnarguesPendientes(db);
    expect(lista, hasLength(1));
    expect(lista.single.id, id);
    expect(lista.single.nombreCliente, 'María');
    expect(lista.single.lineas.map((l) => l.nombre), ['Galletitas', 'Queso barra']);
    expect(lista.single.lineas.first.cantidad, 3);
    expect(lista.single.lineas.last.gramos, 250);
  });

  test('sin stock suficiente no aparta nada: ni el que alcanzaba ni deja el encargue a medias', () async {
    await expectLater(
      crearEncargueApartando(
        db,
        nombreCliente: 'María',
        lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3), LineaEncargueNueva(productoId: queso, gramos: 9000)],
        usuarioId: usuarioId,
      ),
      throwsA(isA<EncargueSinStock>().having((e) => e.nombreProducto, 'producto', 'Queso barra')),
    );
    expect((await producto(galletitas)).stock, 10);
    expect((await producto(queso)).stockGramos, 5000);
    expect(await listarEnarguesPendientes(db), isEmpty);
  });

  test('un encargue sin productos o sin nombre no se crea', () async {
    expect(() => crearEncargueApartando(db, nombreCliente: 'María', lineas: [], usuarioId: usuarioId), throwsArgumentError);
    expect(
      () => crearEncargueApartando(db, nombreCliente: '  ', lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 1)], usuarioId: usuarioId),
      throwsArgumentError,
    );
  });

  test('cancelar devuelve lo apartado con rastro, y cancelar dos veces no devuelve dos veces', () async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );

    await cancelarEncargue(db, id, usuarioId: usuarioId);
    await cancelarEncargue(db, id, usuarioId: usuarioId);

    expect((await producto(galletitas)).stock, 10);
    expect(await listarEnarguesPendientes(db), isEmpty);
    final movs = await (db.select(db.movimientosDeStock)..where((m) => m.motivo.equals('Encargue cancelado: María'))).get();
    expect(movs, hasLength(1));
  });

  test('entregar abre el carrito con lo apartado a los precios de HOY', () async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3), LineaEncargueNueva(productoId: queso, gramos: 250)],
      usuarioId: usuarioId,
    );
    // El precio subió entre que se apartó y que se retira: se cobra el de hoy.
    await (db.update(db.productos)..where((p) => p.id.equals(galletitas))).write(const ProductosCompanion(precioCentavos: Value(200000)));

    final lineas = await lineasParaEntregar(db, id);
    expect(lineas, hasLength(2));
    expect((lineas.first as LineaVentaPorUnidad).cantidad, 3);
    expect((lineas.first as LineaVentaPorUnidad).precioUnitarioCentavos, 200000);
    expect((lineas.last as LineaVentaPesable).gramos, 250);
  });

  test('cobrar la entrega libera lo apartado en la misma transacción: el stock final es el de haber vendido una vez', () async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );
    final lineas = await lineasParaEntregar(db, id);
    final medio = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();

    final (ventaId, _) = await registrarVenta(
      db,
      venta: Venta(lineas: lineas),
      resultado: ResultadoTotalVenta(subtotalCentavos: 450000, recargoCigarrillosCentavos: 0, redondeoCentavos: 0, totalCentavos: 450000),
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medio.id, montoCentavos: 450000, esEfectivo: true)],
      encargueId: id,
    );

    expect((await producto(galletitas)).stock, 7, reason: '10 - 3 vendidas; lo apartado no se descuenta dos veces');
    expect(await listarEnarguesPendientes(db), isEmpty);
    final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingle();
    expect(p.estado, 'RESUELTO');
    expect(p.ventaId, ventaId);
  });

  test('un encargue ya entregado no se puede cancelar (no devuelve stock que ya se vendió)', () async {
    final id = await crearEncargueApartando(
      db,
      nombreCliente: 'María',
      lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
      usuarioId: usuarioId,
    );
    final medio = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
    await registrarVenta(
      db,
      venta: Venta(lineas: await lineasParaEntregar(db, id)),
      resultado: ResultadoTotalVenta(subtotalCentavos: 450000, recargoCigarrillosCentavos: 0, redondeoCentavos: 0, totalCentavos: 450000),
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medio.id, montoCentavos: 450000, esEfectivo: true)],
      encargueId: id,
    );

    await cancelarEncargue(db, id, usuarioId: usuarioId);
    expect((await producto(galletitas)).stock, 7);
  });

  group('entregar y anotar deuda (dueño, 2026-10-03)', () {
    test('queda una deuda por el total a precios de hoy, el stock no se mueve de nuevo y ya no es un encargue', () async {
      final id = await crearEncargueApartando(
        db,
        nombreCliente: 'María',
        lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
        usuarioId: usuarioId,
      );
      // El precio sube antes de entregar: la deuda es a precio de hoy (Regla 4).
      await (db.update(db.productos)..where((p) => p.id.equals(galletitas))).write(const ProductosCompanion(precioCentavos: Value(200000)));

      final total = await entregarEncargueADeuda(db, id, usuarioId: usuarioId);

      expect(total, 600000);
      expect((await producto(galletitas)).stock, 7); // ya estaba descontado al apartar
      expect(await listarEnarguesPendientes(db), isEmpty);
      final deudas = await listarDeudas(db);
      expect(deudas.single.nombreCliente, 'María');
      expect(deudas.single.montoCentavos, 600000);
      expect(deudas.single.detalle, '3 × Galletitas');
    });

    test('hacerlo dos veces no duplica la deuda ni cancelar devuelve stock que ya se fue', () async {
      final id = await crearEncargueApartando(
        db,
        nombreCliente: 'María',
        lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 3)],
        usuarioId: usuarioId,
      );
      await entregarEncargueADeuda(db, id, usuarioId: usuarioId);

      expect(await entregarEncargueADeuda(db, id, usuarioId: usuarioId), isNull);
      await cancelarEncargue(db, id, usuarioId: usuarioId);

      expect(await listarDeudas(db), hasLength(1));
      expect((await producto(galletitas)).stock, 7);
    });
  });
}
