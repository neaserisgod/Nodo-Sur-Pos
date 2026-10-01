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
}
