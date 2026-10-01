import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_rentabilidad.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int cajaId;
  late int sueldoId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    cajaId = (await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle()).id;
    // Un concepto de fijo que hace de "sueldo del dueño".
    sueldoId = (await (db.select(db.gastosFijos)..where((g) => g.nombre.equals('Ayuda fin de semana'))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<void> venta(DateTime fecha, int precio, int? costo) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: Value(fecha),
            subtotalCentavos: precio,
            totalCentavos: precio,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            precioUnitarioCentavos: precio,
            costoUnitarioCentavos: Value(costo),
          ),
        );
  }

  Future<void> movimiento(String tipo, int monto, DateTime fecha, {int? gastoFijoId}) =>
      db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaId,
              usuarioId: usuarioId,
              tipo: tipo,
              montoCentavos: monto,
              fecha: Value(fecha),
              gastoFijoId: Value(gastoFijoId),
            ),
          );

  Future<void> cargarFijos() async {
    final montos = {'Alquiler': 500, 'Luz': 200, 'Internet': 100, 'Ayuda fin de semana': 300};
    for (final c in await db.select(db.gastosFijos).get()) {
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-08', montoCentavos: montos[c.nombre]!);
    }
  }

  test('arma el estado del mes: ventas, fijos sin el sueldo, variables y retiros solo de ese mes', () async {
    await venta(DateTime(2026, 8, 10), 1000, 600);
    await venta(DateTime(2026, 8, 12), 3000, 2000);
    await venta(DateTime(2026, 7, 31), 9000, 1000); // otro mes: no entra
    await cargarFijos();
    await movimiento('GASTO', 150, DateTime(2026, 8, 5)); // gasto rápido (variable)
    await movimiento('GASTO', 500, DateTime(2026, 8, 6), gastoFijoId: sueldoId); // pago de un fijo: NO es variable
    await movimiento('RETIRO', 400, DateTime(2026, 8, 20));
    await movimiento('RETIRO', 999, DateTime(2026, 7, 20)); // otro mes: no entra

    final e = await estadoDeResultadosDelMes(db, '2026-08', sueldoGastoFijoId: sueldoId);

    expect(e.ventasNetasCentavos, 4000);
    expect(e.gananciaBrutaCentavos, 1400);
    expect(e.costoMercaderiaCentavos, 2600);
    expect(e.gastosFijosCentavos, 800); // 500 + 200 + 100, sin el sueldo
    expect(e.sueldoObjetivoCentavos, 300);
    expect(e.gastosVariablesCentavos, 150);
    expect(e.resultadoOperativoCentavos, 450); // 1400 − 800 − 150
    expect(e.retirosDelMesCentavos, 400);
    expect(e.retirableCentavos, 50);
    expect(e.esCompleto, isTrue);
  });

  test('fijos sin cargar no se suman como 0: el estado queda incompleto', () async {
    await venta(DateTime(2026, 8, 10), 1000, 600);
    final e = await estadoDeResultadosDelMes(db, '2026-08');
    expect(e.esCompleto, isFalse);
    expect(e.advertencias.any((a) => a.contains('Faltan montos')), isTrue);
  });

  test('una venta sin costo cargado se reporta aparte y marca el estado incompleto', () async {
    await venta(DateTime(2026, 8, 10), 2000, null);
    await cargarFijos();
    final e = await estadoDeResultadosDelMes(db, '2026-08');
    expect(e.ventasNetasCentavos, 2000);
    expect(e.vendidoSinCostoCentavos, 2000);
    expect(e.gananciaBrutaCentavos, 0);
    expect(e.esCompleto, isFalse);
  });

  test('lo que sobró del mes anterior (completo) se arrastra a lo retirable', () async {
    for (final c in await db.select(db.gastosFijos).get()) {
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-07', montoCentavos: 100);
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-08', montoCentavos: 100);
    }
    await venta(DateTime(2026, 7, 15), 2000, 1000); // julio: ganancia 1000 − fijos 400 = 600
    await venta(DateTime(2026, 8, 15), 1100, 1000); // agosto: ganancia 100 − fijos 400 = −300

    final e = await estadoDeResultadosDelMes(db, '2026-08');
    expect(e.resultadoOperativoCentavos, -300);
    expect(e.retirableCentavos, 300); // −300 + 600 de julio
  });

  test('si el mes anterior está incompleto no se arrastra nada', () async {
    for (final c in await db.select(db.gastosFijos).get()) {
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-08', montoCentavos: 100);
    }
    await venta(DateTime(2026, 7, 15), 2000, 1000); // julio sin fijos cargados
    await venta(DateTime(2026, 8, 15), 2000, 1000); // agosto: 1000 − 400 = 600

    final e = await estadoDeResultadosDelMes(db, '2026-08');
    expect(e.retirableCentavos, 600);
  });

  group('productosPorDebajoDelMargen', () {
    Future<void> producto(
      String nombre, {
      int? costo,
      int? precio,
      String tipoCigarrillo = 'ninguno',
      bool esPesable = false,
      bool activo = true,
    }) =>
        db.into(db.productos).insert(
              ProductosCompanion.insert(
                nombre: nombre,
                tipoCigarrillo: Value(tipoCigarrillo),
                esPesable: Value(esPesable),
                activo: Value(activo),
                costoCentavos: Value(esPesable ? null : costo),
                precioCentavos: Value(esPesable ? null : precio),
                costoPorKiloCentavos: Value(esPesable ? costo : null),
                precioPorKiloCentavos: Value(esPesable ? precio : null),
              ),
            );

    test('lista solo los que dejan menos del margen, del peor al mejor, con su precio sugerido', () async {
      await producto('Bien', costo: 100000, precio: 250000); // 60% ≥ 57%
      await producto('Justo abajo', costo: 100000, precio: 200000); // 50%
      await producto('Muy abajo', costo: 100000, precio: 120000); // 16,67%
      await producto('Queso', costo: 600000, precio: 900000, esPesable: true); // 33,33% por kilo

      final r = await productosPorDebajoDelMargen(db, 5700);
      expect(r.map((p) => p.nombre), ['Muy abajo', 'Queso', 'Justo abajo']);
      expect(r.first.gananciaBp, 1667);
      expect(r.first.precioSugeridoCentavos, 240000); // $1.000 / 0,43 = $2.326 → $2.400
      expect(r[1].esPesable, isTrue);
    });

    test('cigarrillos, inactivos y sin costo o precio no entran', () async {
      await producto('Atado', costo: 400000, precio: 450000, tipoCigarrillo: 'atado');
      await producto('Viejo', costo: 100000, precio: 110000, activo: false);
      await producto('Sin costo', precio: 110000);
      await producto('Sin precio', costo: 100000);
      expect(await productosPorDebajoDelMargen(db, 5700), isEmpty);
    });

    test('un margen inválido (0 o ≥ 100%) no lista nada', () async {
      await producto('X', costo: 100000, precio: 110000);
      expect(await productosPorDebajoDelMargen(db, 0), isEmpty);
      expect(await productosPorDebajoDelMargen(db, 10000), isEmpty);
    });
  });
}
