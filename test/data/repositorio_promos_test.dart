import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart' show productosTodos;
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

/// Creador de promos (El dueño, 2026-09-29): costo de 2 o más artículos + un
/// porcentaje, sin pasarse del precio de lista; se vende como un producto más
/// pero descuenta el stock de cada artículo.
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int provA;
  late int provB;
  late int yerba;
  late int galletitas;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    provA = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'PA', nombre: 'Prov A'));
    provB = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'PB', nombre: 'Prov B'));
    // Yerba: costo 1.000, lista 1.400. Galletitas: costo 500, lista 900.
    yerba = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Yerba',
            proveedorId: Value(provA),
            costoCentavos: const Value(100000),
            precioCentavos: const Value(140000),
            stock: const Value(10),
          ),
        );
    galletitas = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Galletitas',
            proveedorId: Value(provB),
            costoCentavos: const Value(50000),
            precioCentavos: const Value(90000),
            stock: const Value(6),
          ),
        );
  });
  tearDown(() => db.close());

  Future<int> crear({int bp = 3000, String nombre = 'Merienda'}) => guardarPromo(
        db,
        nombre: nombre,
        articulos: [(productoId: yerba, cantidad: 1), (productoId: galletitas, cantidad: 1)],
        gananciaBp: bp,
        usuarioId: usuarioId,
      );

  Future<Producto> leer(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  test('la promo suma los costos, aplica la ganancia y redondea a la centena', () async {
    final id = await crear(); // costo 1.500 / 0,7 = 2.142,86 → 2.200 (lista 2.300)
    final promo = await leer(id);
    expect(promo.esPromo, true);
    expect(promo.costoCentavos, 150000);
    expect(promo.precioCentavos, 220000);
    expect((await listarPromos(db)).single.componentes, hasLength(2));
  });

  test('nunca pasa del precio de lista: con 60% el tope es la suma de las listas', () async {
    final id = await crear(bp: 6000); // 1.500 / 0,4 = 3.750 → 3.800, pero la lista suma 2.300
    expect((await leer(id)).precioCentavos, 230000);
  });

  test('no se guarda con menos de dos artículos, con cigarrillos, pesables o sin costo', () async {
    await expectLater(
      guardarPromo(db, nombre: 'X', articulos: [(productoId: yerba, cantidad: 2)], gananciaBp: 3000, usuarioId: usuarioId),
      throwsArgumentError,
    );
    final atado = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro',
            tipoCigarrillo: const Value('atado'),
            costoCentavos: const Value(400000),
            precioCentavos: const Value(500000),
          ),
        );
    await expectLater(
      guardarPromo(db, nombre: 'X', articulos: [(productoId: yerba, cantidad: 1), (productoId: atado, cantidad: 1)], gananciaBp: 3000, usuarioId: usuarioId),
      throwsArgumentError,
    );
    final sinCosto = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Sin costo', precioCentavos: const Value(100000)));
    await expectLater(
      guardarPromo(db, nombre: 'X', articulos: [(productoId: yerba, cantidad: 1), (productoId: sinCosto, cantidad: 1)], gananciaBp: 3000, usuarioId: usuarioId),
      throwsArgumentError,
    );
  });

  test('si la lista no cubre el costo, no se puede crear (perdería plata)', () async {
    final barato = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Barato', costoCentavos: const Value(100000), precioCentavos: const Value(80000)),
        );
    final barato2 = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Barato 2', costoCentavos: const Value(100000), precioCentavos: const Value(80000)),
        );
    await expectLater(
      guardarPromo(db, nombre: 'X', articulos: [(productoId: barato, cantidad: 1), (productoId: barato2, cantidad: 1)], gananciaBp: 3000, usuarioId: usuarioId),
      throwsArgumentError,
    );
  });

  test('cobrar una promo descuenta el stock de cada artículo y abre la venta en sus líneas', () async {
    final promoId = await crear(); // precio 2.200
    final promo = await leer(promoId);
    final linea = LineaVentaPorUnidad(
      productoId: promo.id.toString(),
      nombreProducto: promo.nombre,
      proveedorId: null,
      cantidad: 2,
      precioUnitarioCentavos: promo.precioCentavos!,
      costoUnitarioCentavos: promo.costoCentavos,
    );
    final venta = Venta(lineas: [linea]);
    final resultado = await calcularResultadoVenta(db, lineas: [linea], medio: ComposicionPago.virtual);
    final (ventaId, stock) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: await pagosSegunMedio(db, medio: ComposicionPago.virtual, totalCentavos: resultado.totalCentavos),
    );

    // 2 promos = 2 yerbas y 2 galletitas.
    expect((await leer(yerba)).stock, 8);
    expect((await leer(galletitas)).stock, 4);
    expect(stock.map((s) => s.productoId).toSet(), {yerba, galletitas});

    // Las líneas guardadas son las de los artículos, con su costo y proveedor,
    // y suman exactamente lo cobrado (2 × $2.200 = $4.400).
    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    expect(lineas.fold<int>(0, (a, l) => a + l.precioUnitarioCentavos * (l.cantidad ?? 1)), 440000);
    final deYerba = lineas.where((l) => l.productoId == yerba);
    expect(deYerba.every((l) => l.proveedorIdFoto == provA && l.costoUnitarioCentavos == 100000), true);
    expect(lineas.where((l) => l.productoId == galletitas).every((l) => l.proveedorIdFoto == provB), true);
    expect(lineas.first.nombreProductoFoto, contains('Merienda'));

    // La reposición sale de los costos reales, por proveedor.
    final repo = await reposicionDelDia(db, sesionId);
    expect(repo.costoRealPorProveedorCentavos[provA.toString()], 200000);
    expect(repo.costoRealPorProveedorCentavos[provB.toString()], 100000);
  });

  test('el precio se reparte según la lista y nunca queda un artículo por encima de su lista', () async {
    final promoId = await crear(bp: 10000); // tope: lista 2.300
    final promo = await leer(promoId);
    final linea = LineaVentaPorUnidad(
      productoId: promo.id.toString(),
      nombreProducto: promo.nombre,
      proveedorId: null,
      cantidad: 1,
      precioUnitarioCentavos: promo.precioCentavos!,
    );
    final resultado = await calcularResultadoVenta(db, lineas: [linea], medio: ComposicionPago.virtual);
    final (ventaId, _) = await registrarVenta(
      db,
      venta: Venta(lineas: [linea]),
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: await pagosSegunMedio(db, medio: ComposicionPago.virtual, totalCentavos: resultado.totalCentavos),
    );
    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    final porProducto = {
      for (final l in lineas) l.productoId!: l.precioUnitarioCentavos * (l.cantidad ?? 1),
    };
    expect(porProducto[yerba], 140000); // tope = su lista
    expect(porProducto[galletitas], 90000);
  });

  test('anular la venta de una promo devuelve el stock de los artículos', () async {
    final promoId = await crear();
    final promo = await leer(promoId);
    final linea = LineaVentaPorUnidad(
      productoId: promo.id.toString(),
      nombreProducto: promo.nombre,
      proveedorId: null,
      cantidad: 1,
      precioUnitarioCentavos: promo.precioCentavos!,
    );
    final resultado = await calcularResultadoVenta(db, lineas: [linea], medio: ComposicionPago.virtual);
    final (ventaId, _) = await registrarVenta(
      db,
      venta: Venta(lineas: [linea]),
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: await pagosSegunMedio(db, medio: ComposicionPago.virtual, totalCentavos: resultado.totalCentavos),
    );
    expect((await leer(yerba)).stock, 9);
    await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'test');
    expect((await leer(yerba)).stock, 10);
    expect((await leer(galletitas)).stock, 6);
  });

  test('las promos no aparecen en las listas de gestión de productos', () async {
    await crear();
    final todos = await productosTodos(db);
    expect(todos.any((p) => p.nombre == 'Merienda'), false);
  });
}
