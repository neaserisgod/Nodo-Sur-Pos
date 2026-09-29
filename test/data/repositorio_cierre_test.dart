import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int medioEfectivoId;
  late int medioMpId;
  late Caja cajaNormal;
  late Caja cajaLata;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle())
            .id;
    medioMpId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle())
            .id;
    cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    cajaLata = await (db.select(db.cajas)..where((c) => c.esLata.equals(true))).getSingle();
  });
  tearDown(() => db.close());

  /// Crea una venta mínima con una línea, para alimentar los agregados del
  /// día sin pasar por toda la pantalla de venta.
  Future<int> crearVenta(
    int sesionId, {
    required int totalCentavos,
    int redondeoCentavos = 0,
    String tipoCigarrillo = 'ninguno',
    int cantidad = 1,
    int? costoUnitarioCentavos,
    int? proveedorIdFoto,
  }) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: totalCentavos - redondeoCentavos,
            redondeoCentavos: Value(redondeoCentavos),
            totalCentavos: totalCentavos,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            proveedorIdFoto: Value(proveedorIdFoto),
            tipoCigarrillo: Value(tipoCigarrillo),
            cantidad: Value(cantidad),
            precioUnitarioCentavos: totalCentavos ~/ cantidad,
            costoUnitarioCentavos: Value(costoUnitarioCentavos),
          ),
        );
    await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: totalCentavos),
        );
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'VENTA',
            montoCentavos: totalCentavos,
            ventaId: Value(ventaId),
          ),
        );
    return ventaId;
  }

  Future<void> crearGasto(
    int sesionId, {
    required int montoCentavos,
    required bool deLata,
    int? medioPagoId,
  }) async {
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: deLata ? cajaLata.id : cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'GASTO',
            montoCentavos: montoCentavos,
            medioPagoId: Value(medioPagoId),
          ),
        );
  }

  /// "Ingreso rápido" (Bruno, 2026-09-13) — mismo `crearGasto` de arriba
  /// pero tipo 'INGRESO'.
  Future<void> crearIngreso(
    int sesionId, {
    required int montoCentavos,
    required bool deLata,
    int? medioPagoId,
  }) async {
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: deLata ? cajaLata.id : cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'INGRESO',
            montoCentavos: montoCentavos,
            medioPagoId: Value(medioPagoId),
          ),
        );
  }

  /// Venta cobrada con Mercado Pago: a diferencia de `crearVenta`, no genera
  /// movimiento de caja (un pago virtual nunca lo hace) — solo un `Pago`,
  /// que es de donde sale `pagosNoEfectivoDelDia`.
  Future<void> crearVentaMp(int sesionId, {required int totalCentavos}) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: totalCentavos,
            totalCentavos: totalCentavos,
          ),
        );
    await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: totalCentavos),
        );
  }

  group('agregados del día', () {
    test('efectivoDeVentasDelDia suma solo las ventas de la caja normal', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVenta(sesionId, totalCentavos: 100000);
      await crearVenta(sesionId, totalCentavos: 50000);

      expect(await efectivoDeVentasDelDia(db, sesionId), 150000);
    });

    test('gastosEnEfectivoDelDia suma solo los gastos con origen caja normal', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearGasto(sesionId, montoCentavos: 20000, deLata: false);
      await crearGasto(sesionId, montoCentavos: 99999, deLata: true); // no debe contar acá

      expect(await gastosEnEfectivoDelDia(db, sesionId), 20000);
    });

    test('gastosEnEfectivoDelDia excluye los gastos pagados con Mercado Pago (Bruno, MP como caja)', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearGasto(sesionId, montoCentavos: 20000, deLata: false);
      await crearGasto(sesionId, montoCentavos: 8000, deLata: false, medioPagoId: medioMpId);

      // Solo el gasto sin medioPagoId (efectivo) cuenta acá — el de MP se
      // resta del lado de MP (gastosPorMpDelDia), nunca de los dos.
      expect(await gastosEnEfectivoDelDia(db, sesionId), 20000);
    });

    test('gastosPorMpDelDia suma solo los gastos marcados con medioPagoId = Mercado Pago', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearGasto(sesionId, montoCentavos: 20000, deLata: false);
      await crearGasto(sesionId, montoCentavos: 8000, deLata: false, medioPagoId: medioMpId);

      expect(await gastosPorMpDelDia(db, sesionId), 8000);
    });

    test(
      '"Ingreso rápido" (2026-09-13): ingresosEnEfectivoDelDia/ingresosPorMpDelDia/ingresosALaLataDelDia '
      'espejan a sus tres pares de gasto',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await crearIngreso(sesionId, montoCentavos: 30000, deLata: false);
        await crearIngreso(sesionId, montoCentavos: 15000, deLata: false, medioPagoId: medioMpId);
        await crearIngreso(sesionId, montoCentavos: 90000, deLata: true);

        expect(await ingresosEnEfectivoDelDia(db, sesionId), 30000);
        expect(await ingresosPorMpDelDia(db, sesionId), 15000);
        expect(await ingresosALaLataDelDia(db, sesionId), 90000);
      },
    );

    test('pagosNoEfectivoDelDia suma lo cobrado por Mercado Pago en las ventas de la sesión', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVenta(sesionId, totalCentavos: 100000); // efectivo, no debe contar
      await crearVentaMp(sesionId, totalCentavos: 45000);
      await crearVentaMp(sesionId, totalCentavos: 12000);

      expect(await pagosNoEfectivoDelDia(db, sesionId), 57000);
    });

    test(
      'pagosNoEfectivoDelDia excluye una venta por MP ya anulada (Bruno, 2026-09-13: '
      '"no toma en cuenta la anulación")',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await crearVentaMp(sesionId, totalCentavos: 45000);
        final ventaAnuladaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 12000, totalCentavos: 12000),
        );
        await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaAnuladaId, medioPagoId: medioMpId, montoCentavos: 12000),
        );

        await anularVenta(db, ventaId: ventaAnuladaId, usuarioId: usuarioId, motivo: 'Prueba');

        // Un pago virtual nunca generó movimiento de caja para revertir
        // (Regla de la fase 3) — la única forma de que deje de contar es
        // que esta consulta la excluya explícitamente.
        expect(await pagosNoEfectivoDelDia(db, sesionId), 45000);
      },
    );

    test('pagosALataDelDia suma los gastos con origen lata (pago a Serra)', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearGasto(sesionId, montoCentavos: 45000, deLata: true);
      await crearGasto(sesionId, montoCentavos: 99999, deLata: false); // no debe contar acá

      expect(await pagosALataDelDia(db, sesionId), 45000);
    });

    test('sin movimientos: los agregados dan 0, no null ni error', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      expect(await efectivoDeVentasDelDia(db, sesionId), 0);
      expect(await gastosEnEfectivoDelDia(db, sesionId), 0);
      expect(await pagosALataDelDia(db, sesionId), 0);
      expect(await redondeoAcumuladoDelDia(db, sesionId), 0);
      expect(await precioListaCigarrillosDelDia(db, sesionId), 0);
      expect(await gastosPorMpDelDia(db, sesionId), 0);
      expect(await pagosNoEfectivoDelDia(db, sesionId), 0);
    });

    test('redondeoAcumuladoDelDia suma el redondeo de todas las ventas de la sesión', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVenta(sesionId, totalCentavos: 100000, redondeoCentavos: 600);
      await crearVenta(sesionId, totalCentavos: 50000, redondeoCentavos: 400);

      expect(await redondeoAcumuladoDelDia(db, sesionId), 1000);
    });

    test('precioListaCigarrillosDelDia suma solo líneas de cigarrillos (atado o suelto)', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVenta(sesionId, totalCentavos: 350000, tipoCigarrillo: 'atado');
      await crearVenta(sesionId, totalCentavos: 20000, tipoCigarrillo: 'suelto');
      await crearVenta(sesionId, totalCentavos: 112000); // almacén común, no cuenta

      expect(await precioListaCigarrillosDelDia(db, sesionId), 370000);
    });

    test(
      'precioListaCigarrillosDelDia y redondeoAcumuladoDelDia excluyen una venta anulada '
      '(Bruno, 2026-09-13: no se separa a la lata algo que ya se revirtió)',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final ventaId = await crearVenta(
          sesionId,
          totalCentavos: 350000,
          redondeoCentavos: 600,
          tipoCigarrillo: 'atado',
        );

        await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'Prueba');

        expect(await precioListaCigarrillosDelDia(db, sesionId), 0);
        expect(await redondeoAcumuladoDelDia(db, sesionId), 0);
      },
    );
  });

  group('PAGO_PROVEEDOR entra en los agregados de egreso (bug: solo se filtraba GASTO)', () {
    late int proveedorId;

    setUp(() async {
      proveedorId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle()).id;
    });

    test('pago en efectivo a un proveedor baja la caja esperada y la diferencia de arqueo da cero', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 1000000);
      await crearVenta(sesionId, totalCentavos: 500000);
      await pagarProveedor(db, proveedorId: proveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 200000);

      expect(await gastosEnEfectivoDelDia(db, sesionId), 200000);

      final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 1300000);
      expect(resumen.efectivoEsperadoCentavos, 1300000); // 1.000.000 + 500.000 - 200.000
      expect(resumen.diferenciaCentavos, 0);
    });

    test('pago por Mercado Pago baja el MP esperado, no la caja de efectivo', () async {
      await actualizarProveedorNivel2(
        db,
        proveedorId: proveedorId,
        colchonReposicionCentavos: 0,
        medioPago: 'Mercado Pago',
      );
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVentaMp(sesionId, totalCentavos: 100000);
      await pagarProveedor(db, proveedorId: proveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 30000);

      expect(await gastosEnEfectivoDelDia(db, sesionId), 0);
      expect(await gastosPorMpDelDia(db, sesionId), 30000);

      final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 0, mpContadoCentavos: 70000);
      expect(resumen.mpEsperadoCentavos, 70000); // 100.000 cobrado - 30.000 pagado
      expect(resumen.mpDiferenciaCentavos, 0);
    });

    test('pago por transferencia o cuenta corriente no mueve ninguna de las dos cajas', () async {
      await actualizarProveedorNivel2(
        db,
        proveedorId: proveedorId,
        colchonReposicionCentavos: 0,
        medioPago: 'Transferencia',
      );
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 1000000);
      await pagarProveedor(db, proveedorId: proveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 200000);

      final otroProveedorId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle()).id;
      await actualizarProveedorNivel2(
        db,
        proveedorId: otroProveedorId,
        colchonReposicionCentavos: 0,
        medioPago: 'Cuenta corriente',
      );
      await pagarProveedor(db, proveedorId: otroProveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 50000);

      expect(await gastosEnEfectivoDelDia(db, sesionId), 0);
      expect(await gastosPorMpDelDia(db, sesionId), 0);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);

      final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 1000000);
      expect(resumen.efectivoEsperadoCentavos, 1000000);
      expect(resumen.diferenciaCentavos, 0);
    });
  });

  group('reposicionDelDia — reusa calcularReposicion del dominio', () {
    test('agrupa por proveedor y separa lo vendido sin costo', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final proveedorF = await db.into(db.proveedores).insert(
            ProveedoresCompanion.insert(codigo: 'ZF', nombre: 'Fiambres test'),
          );

      await crearVenta(sesionId, totalCentavos: 100000, costoUnitarioCentavos: 60000, proveedorIdFoto: proveedorF);
      await crearVenta(sesionId, totalCentavos: 50000); // sin costo cargado (alta rápida o Varios)
      await crearVenta(sesionId, totalCentavos: 350000, tipoCigarrillo: 'atado', costoUnitarioCentavos: 250000);

      final r = await reposicionDelDia(db, sesionId);

      expect(r.costoRealPorProveedorCentavos[proveedorF.toString()], 60000);
      expect(r.vendidoSinCostoCentavos, 50000);
      // el cigarrillo no debe aparecer en ningún lado de la reposición
      expect(r.costoRealPorProveedorCentavos.values.contains(250000), false);
    });

    test(
      'excluye una venta anulada (Bruno, 2026-09-13: el stock ya se repuso, no hay que volver a pedirlo)',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final proveedorF = await db.into(db.proveedores).insert(
          ProveedoresCompanion.insert(codigo: 'ZG', nombre: 'Fiambres test 2'),
        );
        final ventaId = await crearVenta(
          sesionId,
          totalCentavos: 100000,
          costoUnitarioCentavos: 60000,
          proveedorIdFoto: proveedorF,
        );

        await anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'Prueba');

        final r = await reposicionDelDia(db, sesionId);
        expect(r.costoRealPorProveedorCentavos[proveedorF.toString()], isNull);
      },
    );
  });

  group('sesionCerradaAnterior / esUltimaSesion', () {
    test('sin cierres previos: no hay sesión anterior', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      expect(await sesionCerradaAnterior(db, sesionId), isNull);
    });

    test('esUltimaSesion es true para la única sesión que existe', () async {
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      expect(await esUltimaSesion(db, sesionId), true);
    });
  });

  group('calcularResumenCierre — junta todo lo que el domino ya sabe calcular', () {
    test('caso normal: sin cigarrillos ni gastos', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 100000,
      );
      await crearVenta(sesionId, totalCentavos: 50000, redondeoCentavos: 600);

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: 150000,
      );

      // esperada = 100000 + 50000 - 0 = 150000: el redondeo (600) ya está
      // adentro de los 50000 cobrados, no se suma de nuevo.
      expect(resumen.efectivoEsperadoCentavos, 150000);
      expect(resumen.diferenciaCentavos, 0);
      expect(resumen.redondeoAcumuladoCentavos, 600);
      // Ningún concepto de fijos tiene monto cargado este mes: avisa, no inventa.
      expect(resumen.reservaDiariaFijosCentavos, isNull);
    });

    test(
      'trae el desglose por proveedor (Bruno, 2026-09-19: "lo que se debe '
      'separar por cada proveedor" en el detalle de un cierre) — reusa '
      'reposicionDelDia, no lo recalcula de nuevo',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final proveedorId = await db.into(db.proveedores).insert(
          ProveedoresCompanion.insert(codigo: 'ZH', nombre: 'Fiambres test 3'),
        );
        await crearVenta(
          sesionId,
          totalCentavos: 100000,
          costoUnitarioCentavos: 60000,
          proveedorIdFoto: proveedorId,
        );

        final resumen = await calcularResumenCierre(
          db,
          sesionId: sesionId,
          efectivoContadoCentavos: 100000,
        );

        expect(resumen.reposicion.costoRealPorProveedorCentavos[proveedorId.toString()], 60000);
        expect(resumen.reposicion.gananciaPorProveedorCentavos[proveedorId.toString()], 40000);
        // El atajo de conveniencia sigue funcionando para los llamadores viejos.
        expect(resumen.vendidoSinCostoCentavos, resumen.reposicion.vendidoSinCostoCentavos);
      },
    );

    test('con los fijos del mes cargados, calcula la reserva diaria real (fase 7)', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      final mesAnio = mesAnioDe(DateTime.now());
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 75000000);
      }

      final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 0);

      final diasDelMes = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
      final total = 75000000 * conceptos.length;
      expect(resumen.reservaDiariaFijosCentavos, (total / diasDelMes).round());
    });

    test(
        'cigarrillos cobrados por QR con recargo en efectivo: a la lata va el precio de '
        'lista, el recargo queda en el cajón (Regla 6, test obligatorio de Bruno)', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      // Venta en efectivo cualquiera, para que haya cajón suficiente y la
      // separación de abajo no sea parcial.
      await crearVenta(sesionId, totalCentavos: 350000);

      // Un atado de cigarrillos a $3.500 (precio de lista), cobrado por QR
      // (virtual) — dispara el recargo de $300 (Regla 6). Bruno cobra ese
      // recargo en efectivo aparte: pago mixto, la parte en efectivo es
      // EXACTAMENTE el recargo, el resto (precio de lista) va por QR.
      final productoId = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Marlboro Box',
              tipoCigarrillo: const Value('atado'),
              precioCentavos: const Value(350000),
              stock: const Value(10),
            ),
          );
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
      final linea = lineaDesdeProducto(producto, cantidad: 1);
      final venta = Venta(lineas: [linea]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.mixto,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
        pasoRedondeoCentavos: 10000,
      );
      expect(resultado.recargoCigarrillosCentavos, 30000); // $300
      expect(resultado.totalCentavos, 380000); // $3.500 lista + $300 recargo, redondo

      await registrarVenta(
        db,
        venta: venta,
        resultado: resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: 30000, esEfectivo: true),
          PagoARegistrar(medioPagoId: medioMpId, montoCentavos: 350000, esEfectivo: false),
        ],
      );

      expect(await precioListaCigarrillosDelDia(db, sesionId), 350000);

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: 380000, // 350.000 de la venta normal + 30.000 del recargo
      );

      expect(resumen.separacionCigarrillos.esSeparacionParcial, false);
      expect(resumen.separacionCigarrillos.separadoCentavos, 350000); // precio de lista, sin el recargo
      expect(resumen.separacionCigarrillos.quedaEnCajonCentavos, 30000); // exactamente el recargo
    });

    test('separación parcial: no alcanza el efectivo contado (Regla 4)', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await crearVenta(sesionId, totalCentavos: 450000, tipoCigarrillo: 'atado');

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: 100000, // mucho se cobró por QR
      );

      expect(resumen.separacionCigarrillos.separadoCentavos, 100000);
      expect(resumen.separacionCigarrillos.pendienteCentavos, 350000);
      expect(resumen.separacionCigarrillos.esSeparacionParcial, true);
    });

    test('arrastra el pendiente del cierre anterior', () async {
      final sesion1 = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await crearVenta(sesion1, totalCentavos: 450000, tipoCigarrillo: 'atado');
      await cerrarSesion(
        db,
        sesionId: sesion1,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 100000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      final sesion2 = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await crearVenta(sesion2, totalCentavos: 100000, tipoCigarrillo: 'atado');

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesion2,
        efectivoContadoCentavos: 100000,
      );

      // pendiente de ayer (350000) + hoy (100000) = 450000 a separar
      expect(resumen.separacionCigarrillos.separadoCentavos, 100000);
      expect(resumen.separacionCigarrillos.pendienteCentavos, 350000);
    });

    test('resta los pagos a Serra desde la lata para el saldo final', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await crearVenta(sesionId, totalCentavos: 350000, tipoCigarrillo: 'atado');
      await crearGasto(sesionId, montoCentavos: 200000, deLata: true); // le pagó a Serra

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: 350000,
      );

      // lata inicial 0 + separado 350000 - pagado 200000 = 150000
      expect(resumen.lataFinalCentavos, 150000);
    });

    test(
      '"Ingreso rápido" (2026-09-13) suma al esperado de las tres cajas, efectivo/MP/lata',
      () async {
        final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        await crearIngreso(sesionId, montoCentavos: 20000, deLata: false);
        await crearIngreso(sesionId, montoCentavos: 5000, deLata: false, medioPagoId: medioMpId);
        await crearIngreso(sesionId, montoCentavos: 9000, deLata: true);

        final resumen = await calcularResumenCierre(
          db,
          sesionId: sesionId,
          efectivoContadoCentavos: 20000,
          mpContadoCentavos: 5000,
        );

        expect(resumen.efectivoEsperadoCentavos, 20000); // 0 inicial + 20000 ingreso
        expect(resumen.diferenciaCentavos, 0);
        expect(resumen.mpEsperadoCentavos, 5000);
        expect(resumen.lataFinalCentavos, 9000); // 0 inicial + 9000 ingreso, sin separar nada
      },
    );

    test('mpEsperadoCentavos siempre se calcula, aunque no se pase mpContadoCentavos', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVentaMp(sesionId, totalCentavos: 50000);
      await crearGasto(sesionId, montoCentavos: 8000, deLata: false, medioPagoId: medioMpId);

      final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 0);

      expect(resumen.mpEsperadoCentavos, 42000); // 50000 - 8000
      expect(resumen.mpDiferenciaCentavos, isNull); // oculta hasta escribir el MP contado
    });

    test('mpDiferenciaCentavos se calcula recién cuando se pasa mpContadoCentavos', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVentaMp(sesionId, totalCentavos: 50000);

      final resumen = await calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 48000, // MP ya descontó su comisión
      );

      expect(resumen.mpEsperadoCentavos, 50000);
      expect(resumen.mpDiferenciaCentavos, -2000);
    });
  });

  group('cerrarSesion — persiste exactamente lo que calcularResumenCierre calculó', () {
    test('guarda estado, fechas y todos los montos', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 100000,
      );
      await crearVenta(sesionId, totalCentavos: 50000, redondeoCentavos: 600);

      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 150000,
        mpContadoCentavos: 25000,
        lataContadoCentavos: 0,
        nota: 'todo bien',
      );

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'CERRADA');
      expect(sesion.fechaCierre, isNotNull);
      expect(sesion.usuarioCerroId, usuarioId);
      expect(sesion.efectivoContadoCentavos, 150000);
      expect(sesion.efectivoEsperadoCentavos, 150000);
      expect(sesion.diferenciaCentavos, 0);
      expect(sesion.mpContadoCentavos, 25000);
      expect(sesion.mpEsperadoCentavos, 0); // sin ventas por MP en este caso
      expect(sesion.mpDiferenciaCentavos, 25000); // contado - esperado = 25000 - 0
      expect(sesion.nota, 'todo bien');
    });
  });

  group('reabrirSesion — solo la última, con confirmación externa', () {
    test('reabre la última sesión cerrada', () async {
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      await reabrirSesion(db, sesionId: sesionId);

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'ABIERTA');
    });

    test('no deja reabrir una sesión vieja si ya se abrió una nueva después', () async {
      final sesion1 = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await cerrarSesion(
        db,
        sesionId: sesion1,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );
      await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      expect(() => reabrirSesion(db, sesionId: sesion1), throwsStateError);
    });
  });

  group('esDeOtroDia', () {
    test('una fecha de hoy no es "de otro día"', () {
      expect(esDeOtroDia(DateTime.now()), false);
    });

    test('una fecha de ayer sí es "de otro día"', () {
      expect(esDeOtroDia(DateTime.now().subtract(const Duration(days: 1))), true);
    });
  });

  group('sesionCerradaHoyParaPrecarga — precarga del turno entrante', () {
    test('null si nunca se cerró ninguna sesión', () async {
      expect(await sesionCerradaHoyParaPrecarga(db), isNull);
    });

    test('la sesión cerrada hoy, si la hay (cambio de turno)', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 250000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      final resultado = await sesionCerradaHoyParaPrecarga(db);
      expect(resultado?.id, sesionId);
    });

    test('null si la última cerrada fue de un día anterior (primera apertura del día)', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 250000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
        fechaCierre: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(await sesionCerradaHoyParaPrecarga(db), isNull);
    });
  });

  group('fondoInicialSugeridoCentavos — sugerencia de apertura', () {
    test('null si nunca se cerró ninguna sesión (primera apertura)', () async {
      expect(await fondoInicialSugeridoCentavos(db), isNull);
    });

    test('el efectivo contado menos lo separado a la lata, si se cerró hoy', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 250000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      expect(await fondoInicialSugeridoCentavos(db), 250000);
    });

    test('null si la última cerrada fue de un día anterior (primera apertura del día)', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 250000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
        fechaCierre: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(await fondoInicialSugeridoCentavos(db), isNull);
    });
  });

  group('estadoCajaEnVivo / cantidadVentasDelDia — "arqueo" sin contar a mano', () {
    test('efectivo y MP esperados salen de las mismas fórmulas del cierre, sin pedir contado', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
      await crearVenta(sesionId, totalCentavos: 50000);
      await crearVentaMp(sesionId, totalCentavos: 30000);
      await crearGasto(sesionId, montoCentavos: 5000, deLata: false);

      final estado = await estadoCajaEnVivo(db, sesionId);

      // 100000 inicial + 50000 de ventas en efectivo - 5000 de gasto = 145000.
      expect(estado.efectivoEsperadoCentavos, 145000);
      // Nada de MP se gastó todavía.
      expect(estado.mpEsperadoCentavos, 30000);
    });

    test('cantidadVentasDelDia cuenta las ventas de la sesión, sin importar el medio', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await crearVenta(sesionId, totalCentavos: 10000);
      await crearVenta(sesionId, totalCentavos: 20000);
      await crearVentaMp(sesionId, totalCentavos: 30000);

      expect(await cantidadVentasDelDia(db, sesionId), 3);
    });

    test('una sesión recién abierta, sin ventas, da efectivo = inicial y todo lo demás en cero', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 250000);

      final estado = await estadoCajaEnVivo(db, sesionId);

      expect(estado.efectivoEsperadoCentavos, 250000);
      expect(estado.mpEsperadoCentavos, 0);
      expect(await cantidadVentasDelDia(db, sesionId), 0);
    });
  });

  group('cerrarSesion — bloqueo contra un cierre concurrente', () {
    test('cerrar una sesión ya CERRADA tira SesionYaNoAbiertaException', () async {
      // Bruno, 2026-09-19: "aislar los usuarios para que no se pisen" — un
      // segundo cierre (ej. desde otro dispositivo) no debe pisar el
      // primero con un UPDATE que "tiene éxito" sin haber tocado nada.
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      await expectLater(
        cerrarSesion(
          db,
          sesionId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 0,
          lataContadoCentavos: 0,
        ),
        throwsA(isA<SesionYaNoAbiertaException>()),
      );
    });
  });

  group('lata que se arrastra al abrir (REGLAS §10: "lo último contado")', () {
    test('si la lata contada no coincidía con la esperada, arranca con lo contado', () async {
      final primera = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0, lataInicialCentavos: 11500000);
      await cerrarSesion(
        db,
        sesionId: primera,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 12500000,
      );
      final cerrada = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(primera))).getSingle();
      expect(cerrada.lataFinalCentavos, 11500000); // lo esperado
      expect(await lataQueSeArrastraCentavos(db), 12500000);
      expect(await lataInicialSugeridoCentavos(db), 12500000);

      final segunda = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final abierta = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(segunda))).getSingle();
      expect(abierta.lataInicialCentavos, 12500000);
    });
  });

  test('la ganancia sale neta del descuento de la venta (revisión 2026-09-29)', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final proveedorId = await db.into(db.proveedores).insert(
          ProveedoresCompanion.insert(codigo: 'ZD', nombre: 'Prov descuento'),
        );
    // Lista 100000, costo 60000, descuento 15% (15000) -> cobrado 85000.
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 100000,
            descuentoCentavos: const Value(15000),
            totalCentavos: 85000,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'P',
            proveedorIdFoto: Value(proveedorId),
            cantidad: const Value(1),
            precioUnitarioCentavos: 100000,
            costoUnitarioCentavos: const Value(60000),
          ),
        );
    final r = await reposicionDelDia(db, sesionId);
    expect(r.gananciaPorProveedorCentavos[proveedorId.toString()], 25000);
    expect(r.vendidoPorProveedorCentavos[proveedorId.toString()], 85000);
  });
}
