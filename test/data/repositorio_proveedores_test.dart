import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/domain/periodo.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int serraId;
  late int serraCigarrosId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    serraId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle()).id;
    serraCigarrosId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('SC'))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<void> crearVenta({
    required DateTime fecha,
    required int proveedorId,
    required int precioCentavos,
    int? costoCentavos,
    bool esCigarrillo = false,
  }) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: Value(fecha),
            subtotalCentavos: precioCentavos,
            totalCentavos: precioCentavos,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            proveedorIdFoto: Value(proveedorId),
            tipoCigarrillo: Value(esCigarrillo ? 'atado' : 'ninguno'),
            precioUnitarioCentavos: precioCentavos,
            costoUnitarioCentavos: Value(costoCentavos),
          ),
        );
  }

  group('resumenProveedoresNivel1', () {
    test('stock (a precio) y costo se calculan por separado — cuatro cifras, no tres', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              proveedorId: Value(serraId),
              precioCentavos: const Value(150000),
              costoCentavos: const Value(80000),
              stock: const Value(10),
            ),
          );

      final resultados = await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));
      final serra = resultados.firstWhere((r) => r.proveedor.id == serraId);

      expect(serra.stockValorizadoCentavos, 1500000); // a precio: "cuánto vale en la góndola"
      expect(serra.costoValorizadoCentavos, 800000); // a costo: "cuánto me costó"
      expect(serra.productosSinCostoCantidad, 0);
      expect(serra.productosSinPrecioCantidad, 0);
    });

    test('producto sin costo ni precio: no entra a ninguno de los dos valorizados, se cuenta aparte en cada uno', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Alta rápida', proveedorId: Value(serraId), stock: const Value(5)),
          );

      final resultados = await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));
      final serra = resultados.firstWhere((r) => r.proveedor.id == serraId);

      expect(serra.stockValorizadoCentavos, 0);
      expect(serra.costoValorizadoCentavos, 0);
      expect(serra.productosSinCostoCantidad, 1);
      expect(serra.productosSinPrecioCantidad, 1);
    });

    test('vendido y ganancia se calculan con calcularGananciaBruta, dentro del período', () async {
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);
      // Fuera del mes de "ahora" (2026-09-15): no debería contar.
      await crearVenta(fecha: DateTime(2026, 8, 20), proveedorId: serraId, precioCentavos: 5000, costoCentavos: 3000);

      final resultados = await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));
      final serra = resultados.firstWhere((r) => r.proveedor.id == serraId);

      expect(serra.vendidoCentavos, 1000);
      expect(serra.gananciaBrutaCentavos, 400);
    });

    test('Serra Cigarros (SC) aparece con su venta real — a diferencia de reposicionActual, acá no se excluye', () async {
      await crearVenta(
        fecha: DateTime(2026, 9, 10),
        proveedorId: serraCigarrosId,
        precioCentavos: 5000,
        costoCentavos: 4700,
        esCigarrillo: true,
      );

      final resultados = await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resultados.any((r) => r.proveedor.id == serraCigarrosId), isTrue);
      final sc = resultados.firstWhere((r) => r.proveedor.id == serraCigarrosId);
      expect(sc.vendidoCentavos, 5000);
      expect(sc.gananciaBrutaCentavos, 300);

      // reposicionActual, en cambio, sigue excluyendo a SC (Regla 6) — no
      // se tocó ese comportamiento, es un archivo distinto con otro fin.
      final reposicion = await reposicionActual(db);
      expect(reposicion.any((r) => r.proveedor.id == serraCigarrosId), isFalse);
    });

    test('"desde el último pago" usa la fecha propia de cada proveedor', () async {
      await (db.update(db.proveedores)..where((p) => p.id.equals(serraId)))
          .write(ProveedoresCompanion(ultimoPagoFecha: Value(DateTime(2026, 9, 5))));

      await crearVenta(fecha: DateTime(2026, 9, 1), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 2000, costoCentavos: 1200);

      final resultados =
          await resumenProveedoresNivel1(db, periodo: PeriodoResumen.desdeUltimoPago, ahora: DateTime(2026, 9, 15));
      final serra = resultados.firstWhere((r) => r.proveedor.id == serraId);

      expect(serra.vendidoCentavos, 2000); // solo la venta del 10, después del pago del 5
    });

    test('"desde el último pago" sin ningún pago registrado: cuenta desde siempre', () async {
      await crearVenta(fecha: DateTime(2020, 1, 1), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);

      final resultados =
          await resumenProveedoresNivel1(db, periodo: PeriodoResumen.desdeUltimoPago, ahora: DateTime(2026, 9, 15));
      final serra = resultados.firstWhere((r) => r.proveedor.id == serraId);

      expect(serra.vendidoCentavos, 1000);
    });

    test('proveedores sin venta en el período van al final (corrección post-revisión)', () async {
      // Solo Serra vende en el período — el resto (Mazzota, Coca Cola,
      // Wesley, Puelche, etc., del catálogo real de 15) queda en $0.
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);

      final resultados = await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));
      final indiceSerra = resultados.indexWhere((r) => r.proveedor.id == serraId);

      expect(resultados.first.proveedor.id, serraId);
      expect(indiceSerra, 0);
      for (var i = 1; i < resultados.length; i++) {
        expect(resultados[i].sinMovimiento, isTrue);
      }
    });
  });

  group('resumenTodosLosProductos (fase 13, ítem "Todos")', () {
    test('"Varios" (sentinela sin precio/costo) no infla el conteo de "sin costo"/"sin precio"', () async {
      final resumen = await resumenTodosLosProductos(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resumen.productosSinCostoCantidad, 0);
      expect(resumen.productosSinPrecioCantidad, 0);
    });

    test('suma stock valorizado de productos con Y sin proveedor', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Con proveedor',
              proveedorId: Value(serraId),
              precioCentavos: const Value(100000),
              costoCentavos: const Value(60000),
              stock: const Value(2),
            ),
          );
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Huérfano',
              precioCentavos: const Value(50000),
              costoCentavos: const Value(30000),
              stock: const Value(1),
            ),
          );

      final resumen = await resumenTodosLosProductos(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resumen.stockValorizadoCentavos, 250000); // 100000*2 + 50000*1
      expect(resumen.costoValorizadoCentavos, 150000); // 60000*2 + 30000*1
    });

    test('vendido/ganancia suman todas las líneas del período, sin filtrar proveedor', () async {
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);
      await crearVenta(fecha: DateTime(2026, 8, 20), proveedorId: serraId, precioCentavos: 5000, costoCentavos: 3000);

      final resumen = await resumenTodosLosProductos(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resumen.vendidoCentavos, 1000); // solo septiembre
    });

    test('"desde el último pago" sin proveedor puntual cuenta desde siempre', () async {
      await crearVenta(fecha: DateTime(2020, 1, 1), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);

      final resumen =
          await resumenTodosLosProductos(db, periodo: PeriodoResumen.desdeUltimoPago, ahora: DateTime(2026, 9, 15));

      expect(resumen.vendidoCentavos, 1000);
    });
  });

  group('resumenProductosSinProveedor (fase 13, ítem "Sin proveedor")', () {
    test('solo cuenta el stock de productos huérfanos', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Con proveedor',
              proveedorId: Value(serraId),
              precioCentavos: const Value(100000),
              costoCentavos: const Value(60000),
              stock: const Value(2),
            ),
          );
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Huérfano',
              precioCentavos: const Value(50000),
              costoCentavos: const Value(30000),
              stock: const Value(1),
            ),
          );

      final resumen =
          await resumenProductosSinProveedor(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resumen.stockValorizadoCentavos, 50000);
      expect(resumen.costoValorizadoCentavos, 30000);
    });

    test('vendido/ganancia solo de líneas sin proveedor foto', () async {
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 1000, costoCentavos: 600);

      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: Value(DateTime(2026, 9, 11)),
              subtotalCentavos: 2000,
              totalCentavos: 2000,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Huérfano',
              precioUnitarioCentavos: 2000,
              costoUnitarioCentavos: const Value(1200),
            ),
          );

      final resumen =
          await resumenProductosSinProveedor(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));

      expect(resumen.vendidoCentavos, 2000);
      expect(resumen.gananciaBrutaCentavos, 800);
    });
  });

  group('ventas anuladas no cuentan (Bruno, 2026-09-26)', () {
    test('ni en lo vendido ni en la ganancia del proveedor, ni en "Todos"', () async {
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 100000, costoCentavos: 60000);
      await crearVenta(fecha: DateTime(2026, 9, 10), proveedorId: serraId, precioCentavos: 50000, costoCentavos: 30000);
      await db.customStatement('UPDATE ventas SET anulada_en = 1 WHERE id = (SELECT MAX(id) FROM ventas)');

      final serra = (await resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15)))
          .firstWhere((r) => r.proveedor.id == serraId);
      expect(serra.vendidoCentavos, 100000);
      expect(serra.gananciaBrutaCentavos, 40000);

      final todos = await resumenTodosLosProductos(db, periodo: PeriodoResumen.mes, ahora: DateTime(2026, 9, 15));
      expect(todos.vendidoCentavos, 100000);
    });
  });
}
