import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int alquilerId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    alquilerId =
        (await (db.select(db.gastosFijos)..where((g) => g.nombre.equals('Alquiler'))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<void> crearVenta({
    required DateTime fecha,
    required int precioCentavos,
    int? costoCentavos,
    String tipoCigarrillo = 'ninguno',
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
            tipoCigarrillo: Value(tipoCigarrillo),
            precioUnitarioCentavos: precioCentavos,
            costoUnitarioCentavos: Value(costoCentavos),
          ),
        );
  }

  group('fijosDelMes', () {
    test('avisa qué falta en vez de inventar un total, si algún concepto activo no tiene monto ese mes', () async {
      final r = await fijosDelMes(db, '2026-08');
      expect(r.total, isNull);
      expect(r.faltantes, containsAll(['Alquiler', 'Ayuda fin de semana', 'Luz', 'Internet']));
    });

    test('con todos los conceptos cargados, suma el total del mes', () async {
      final conceptos = await (db.select(db.gastosFijos)).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-08', montoCentavos: 10000000);
      }
      final r = await fijosDelMes(db, '2026-08');
      expect(r.total, 40000000);
      expect(r.faltantes, isEmpty);
    });

    test('cargar el mismo concepto y mes dos veces actualiza, no duplica (el alquiler puede corregirse)', () async {
      await cargarMontoDelMes(db, gastoFijoId: alquilerId, mesAnio: '2026-08', montoCentavos: 90000000);
      await cargarMontoDelMes(db, gastoFijoId: alquilerId, mesAnio: '2026-08', montoCentavos: 93500000);

      final filas = await (db.select(db.gastosFijosMontos)
            ..where((m) => m.gastoFijoId.equals(alquilerId) & m.mesAnio.equals('2026-08')))
          .get();
      expect(filas, hasLength(1));
      expect(filas.single.montoCentavos, 93500000);
    });

    test('un mes distinto no reescribe el monto de otro mes (el alquiler sube sin tocar el pasado)', () async {
      await cargarMontoDelMes(db, gastoFijoId: alquilerId, mesAnio: '2026-07', montoCentavos: 90000000);
      await cargarMontoDelMes(db, gastoFijoId: alquilerId, mesAnio: '2026-08', montoCentavos: 93500000);

      final julio = await (db.select(db.gastosFijosMontos)
            ..where((m) => m.gastoFijoId.equals(alquilerId) & m.mesAnio.equals('2026-07')))
          .getSingle();
      expect(julio.montoCentavos, 90000000);
    });
  });

  group('fijosPagadosDelMes', () {
    test('suma solo pagos con concepto de fijo asociado, del mes pedido', () async {
      final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormal.id,
              usuarioId: usuarioId,
              tipo: 'GASTO',
              montoCentavos: 93500000,
              fecha: Value(DateTime(2026, 8, 5)),
              gastoFijoId: Value(alquilerId),
            ),
          );
      // Gasto rápido genérico, sin concepto de fijo: no debería contar.
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormal.id,
              usuarioId: usuarioId,
              tipo: 'GASTO',
              montoCentavos: 500000,
              fecha: Value(DateTime(2026, 8, 6)),
            ),
          );
      // Mismo concepto, mes distinto: no debería contar para agosto.
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormal.id,
              usuarioId: usuarioId,
              tipo: 'GASTO',
              montoCentavos: 90000000,
              fecha: Value(DateTime(2026, 7, 30)),
              gastoFijoId: Value(alquilerId),
            ),
          );

      expect(await fijosPagadosDelMes(db, '2026-08'), 93500000);
    });
  });

  group('registrarPagoFijo', () {
    test('crea un movimiento de GASTO en la caja normal con el concepto asociado', () async {
      await registrarPagoFijo(
        db,
        gastoFijoId: alquilerId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 93500000,
      );

      final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
      final movimiento = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.gastoFijoId.equals(alquilerId)))
          .getSingle();
      expect(movimiento.tipo, 'GASTO');
      expect(movimiento.cajaId, cajaNormal.id);
      expect(movimiento.montoCentavos, 93500000);
      expect(movimiento.medioPagoId, isNull);
    });

    test('pagadoConMp: sigue en la caja normal, pero queda marcado con medioPagoId de Mercado Pago', () async {
      await registrarPagoFijo(
        db,
        gastoFijoId: alquilerId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 93500000,
        pagadoConMp: true,
      );

      final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
      final medioMp =
          await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
      final movimiento = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.gastoFijoId.equals(alquilerId)))
          .getSingle();
      expect(movimiento.cajaId, cajaNormal.id);
      expect(movimiento.medioPagoId, medioMp.id);
    });

    test('sin fecha explícita, usa ahora', () async {
      await registrarPagoFijo(
        db,
        gastoFijoId: alquilerId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 93500000,
      );

      final movimiento = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.gastoFijoId.equals(alquilerId)))
          .getSingle();
      // Tolerancia por el redondeo de precisión de drift al guardar la
      // fecha (segundos, no milisegundos) — no interesa el instante exacto,
      // solo que no haya quedado una fecha vieja o fija por error.
      expect(DateTime.now().difference(movimiento.fecha).inSeconds.abs(), lessThan(10));
    });

    test('con fecha explícita, el pago queda registrado en esa fecha (Bruno paga un día y carga otro)', () async {
      await registrarPagoFijo(
        db,
        gastoFijoId: alquilerId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 93500000,
        fecha: DateTime(2026, 7, 31),
      );

      final movimiento = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.gastoFijoId.equals(alquilerId)))
          .getSingle();
      expect(movimiento.fecha, DateTime(2026, 7, 31));
      // el pago cuenta para julio, no para el mes en que se cargó.
      expect(await fijosPagadosDelMes(db, '2026-07'), 93500000);
      expect(await fijosPagadosDelMes(db, '2026-08'), 0);
    });
  });

  group('gananciaBrutaDelMes', () {
    test('suma la ganancia real del mes pedido, cigarrillos incluidos, y excluye otros meses', () async {
      await crearVenta(fecha: DateTime(2026, 8, 10), precioCentavos: 1000, costoCentavos: 650);
      await crearVenta(
        fecha: DateTime(2026, 8, 11),
        precioCentavos: 1000,
        costoCentavos: 800,
        tipoCigarrillo: 'atado',
      );
      await crearVenta(fecha: DateTime(2026, 7, 31), precioCentavos: 5000, costoCentavos: 1000);

      final r = await gananciaBrutaDelMes(db, '2026-08');
      expect(r.gananciaBrutaCentavos, 550); // (1000-650) + (1000-800)
      expect(r.ventaConCostoCentavos, 2000);
    });

    test('vendido sin costo cargado no se pierde, se reporta aparte', () async {
      await crearVenta(fecha: DateTime(2026, 8, 10), precioCentavos: 2000, costoCentavos: null);

      final r = await gananciaBrutaDelMes(db, '2026-08');
      expect(r.gananciaBrutaCentavos, 0);
      expect(r.vendidoSinCostoCentavos, 2000);
    });
  });

  group('fijosPendientesDelMes (Regla 13: dato informativo junto al retiro)', () {
    test('fijos incompletos: null ("avisar antes que inventar")', () async {
      expect(await fijosPendientesDelMes(db, '2026-08'), isNull);
    });

    test('fijos completos, nada pagado: pendiente = total', () async {
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: '2026-08', montoCentavos: 2000000);
      }
      final totalFijos = 2000000 * conceptos.length;

      expect(await fijosPendientesDelMes(db, '2026-08'), totalFijos);
    });

    test('descuenta lo ya pagado ese mes, nunca queda negativo', () async {
      const mesAnio = '2026-08';
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 25000000);
      }
      final totalFijos = 25000000 * conceptos.length;
      await registrarPagoFijo(
        db,
        gastoFijoId: alquilerId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: totalFijos, // pagó todo de una
        fecha: DateTime(2026, 8, 15),
      );

      expect(await fijosPendientesDelMes(db, mesAnio), 0);
    });
  });

  group('gananciaBrutaDelMes sin ventas anuladas (Bruno, 2026-09-26)', () {
    test('una venta anulada no suma ganancia del mes', () async {
      await crearVenta(fecha: DateTime(2026, 8, 10), precioCentavos: 1000, costoCentavos: 650);
      await crearVenta(fecha: DateTime(2026, 8, 11), precioCentavos: 5000, costoCentavos: 1000);
      await db.customStatement('UPDATE ventas SET anulada_en = 1 WHERE id = (SELECT MAX(id) FROM ventas)');

      final r = await gananciaBrutaDelMes(db, '2026-08');
      expect(r.gananciaBrutaCentavos, 350);
      expect(r.ventaConCostoCentavos, 1000);
    });
  });
}
