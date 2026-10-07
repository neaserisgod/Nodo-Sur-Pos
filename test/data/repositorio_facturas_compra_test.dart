import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_facturas_compra.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/domain/aplicar_factura.dart';

import '../helpers/base_para_tests.dart';

/// Aplicar y deshacer una factura de compra (El dueño, 2026-10-07).
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int elpar;
  late int crema;

  setUp(() async {
    db = baseDeTest();
    usuarioId = (await db.select(db.usuarios).get()).first.id;
    elpar = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'EL', nombre: 'Elpar'));
    crema = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Crema 200', proveedorId: Value(elpar), precioCentavos: const Value(300000), costoCentavos: const Value(180000), stock: const Value(3)),
        );
  });
  tearDown(() => db.close());

  Future<Producto> producto(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  Future<ResultadoAplicarFactura> aplicar({
    String? numero = '0011-00266439',
    List<LineaParaAplicar>? lineas,
    bool sumarStock = true,
    int? total = 877421,
  }) =>
      aplicarFactura(
        db,
        proveedorId: elpar,
        numero: numero,
        tipo: 'A',
        totalImpresoCentavos: total,
        lineas: lineas ?? [LineaParaAplicar(productoId: crema, unidades: 4, totalCentavos: 877421)],
        sumarStock: sumarStock,
        usuarioId: usuarioId,
      );

  group('aplicar', () {
    test('carga la deuda, suma el stock con rastro y pone el costo nuevo', () async {
      await aplicar();
      expect(await saldoDeuda(db, elpar), 877421);
      final p = await producto(crema);
      expect(p.stock, 7);
      expect(p.costoCentavos, 219400);
      expect(p.precioCentavos, 300000, reason: 'sin % del proveedor el precio no se toca');
      final movs = await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(crema))).get();
      expect(movs.single.motivo, 'Compra · Factura 0011-00266439');
      expect(movs.single.stockAnterior, 3);
      expect(movs.single.stockPosterior, 7);
      expect(await historialDelProducto(db, crema), isNotEmpty, reason: 'el costo nuevo queda en el historial');
    });

    test('con % del proveedor el precio se recalcula; con precio fijo, no', () async {
      await (db.update(db.proveedores)..where((p) => p.id.equals(elpar))).write(const ProveedoresCompanion(markupBp: Value(5000)));
      final fijo = await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Dulce', proveedorId: Value(elpar), precioCentavos: const Value(100000), costoCentavos: const Value(50000), precioFijo: const Value(true)),
          );
      await aplicar(lineas: [
        LineaParaAplicar(productoId: crema, unidades: 4, totalCentavos: 877421),
        LineaParaAplicar(productoId: fijo, unidades: 1, totalCentavos: 60000),
      ], total: null);
      expect((await producto(crema)).precioCentavos, greaterThan(300000));
      expect((await producto(fijo)).precioCentavos, 100000);
      expect((await producto(fijo)).costoCentavos, 60000);
    });

    test('"No va" entra en la deuda pero no toca el producto; sin la casilla de stock, el stock no cambia', () async {
      final otro = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Otro', stock: const Value(1)));
      await aplicar(sumarStock: false, total: null, lineas: [
        LineaParaAplicar(productoId: crema, unidades: 4, totalCentavos: 877421),
        LineaParaAplicar(productoId: otro, unidades: 2, totalCentavos: 10000, noVa: true),
      ]);
      expect(await saldoDeuda(db, elpar), 887421);
      expect((await producto(crema)).stock, 3);
      expect((await producto(crema)).costoCentavos, 219400);
      expect((await producto(otro)).stock, 1);
    });

    test('la misma factura no se carga dos veces (aunque cambien los ceros); deshecha, sí', () async {
      final r = await aplicar();
      expect(() => aplicar(numero: '11-266439'), throwsA(isA<FacturaYaCargadaException>()));
      await deshacerFactura(db, facturaId: r.facturaId, usuarioId: usuarioId);
      await aplicar();
      expect(await saldoDeuda(db, elpar), 877421);
    });

    test('lo que falta revisar o una nota de crédito no se aplica, y no deja nada a medias', () async {
      expect(() => aplicar(lineas: const [LineaParaAplicar(productoId: null, unidades: 1, totalCentavos: 100)]), throwsArgumentError);
      expect(
        () => aplicarFactura(db, proveedorId: elpar, tipo: 'NC', totalImpresoCentavos: 100, lineas: [LineaParaAplicar(productoId: crema, unidades: 1, totalCentavos: 100)], sumarStock: true, usuarioId: usuarioId),
        throwsArgumentError,
      );
      expect(await saldoDeuda(db, elpar), 0);
      expect(await db.select(db.facturasCompra).get(), isEmpty);
    });

    test('un producto por peso no se toca y se avisa', () async {
      final queso = await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Queso', esPesable: const Value(true), precioPorKiloCentavos: const Value(900000), stockGramos: const Value(1000)),
          );
      final r = await aplicar(total: null, lineas: [LineaParaAplicar(productoId: queso, unidades: 3, totalCentavos: 1500000)]);
      expect(r.pesablesSinTocar, ['Queso']);
      expect((await producto(queso)).stockGramos, 1000);
      expect(await saldoDeuda(db, elpar), 1500000);
    });
  });

  group('deshacer', () {
    test('anula la deuda, resta el stock y vuelve al costo de antes', () async {
      final r = await aplicar();
      final d = await deshacerFactura(db, facturaId: r.facturaId, usuarioId: usuarioId);
      expect(d.costosQueQuedaron, isEmpty);
      expect(await saldoDeuda(db, elpar), 0);
      final p = await producto(crema);
      expect(p.stock, 3);
      expect(p.costoCentavos, 180000);
      expect(() => deshacerFactura(db, facturaId: r.facturaId, usuarioId: usuarioId), throwsArgumentError);
    });

    test('un costo cambiado a mano después no se pisa, y se avisa', () async {
      final r = await aplicar();
      await cargarCostoProducto(db, productoId: crema, costoCentavos: 250000, usuarioId: usuarioId);
      final d = await deshacerFactura(db, facturaId: r.facturaId, usuarioId: usuarioId);
      expect(d.costosQueQuedaron, ['Crema 200']);
      expect((await producto(crema)).costoCentavos, 250000);
      expect((await producto(crema)).stock, 3);
    });

    test('con un pago a cuenta de la factura, pide anular el pago primero y no toca nada', () async {
      final r = await aplicar();
      await pagarDeuda(db, proveedorId: elpar, montoCentavos: 877421, origen: OrigenPagoDeuda.fuera, usuarioId: usuarioId);
      expect(
        () => deshacerFactura(db, facturaId: r.facturaId, usuarioId: usuarioId),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'mensaje', contains('anulá primero ese pago'))),
      );
      expect((await producto(crema)).stock, 7);
    });

    test('el cargo de la factura se reconoce en la cuenta corriente', () async {
      final r = await aplicar();
      final cargo = (await listarMovimientosDeuda(db, elpar)).single;
      expect(cargo.nota, 'Factura 0011-00266439');
      expect((await facturaDelMovimientoDeuda(db, cargo.id))!.id, r.facturaId);
      expect(await movimientosDeudaConFactura(db, elpar), {cargo.id});
    });
  });

  group('precio que quedaría (para avisar antes de aplicar)', () {
    test('sin %, el de hoy; con %, el automático; sin cambio de costo, el de hoy', () async {
      final p = await producto(crema);
      expect(await precioTrasCambioDeCosto(db, p, costoNuevoCentavos: 400000), 300000);
      await (db.update(db.proveedores)..where((x) => x.id.equals(elpar))).write(const ProveedoresCompanion(markupBp: Value(5000)));
      expect(await precioTrasCambioDeCosto(db, p, costoNuevoCentavos: 200000), 400000); // 50 % de ganancia sobre el precio: 2.000 / 0,5
      expect(await precioTrasCambioDeCosto(db, p, costoNuevoCentavos: 180000), 300000, reason: 'mismo costo: no cambia');
    });
  });
}
