import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart' show anularVenta;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  group('sesionAbierta / abrirSesion', () {
    test('sin sesiones todavía: no hay ninguna abierta', () async {
      expect(await sesionAbierta(db), isNull);
    });

    test(
      'abrir una sesión nueva: lata inicial en 0 si nunca hubo una anterior',
      () async {
        final id = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 15000000,
        );
        final sesion = await sesionAbierta(db);
        expect(sesion!.id, id);
        expect(sesion.lataInicialCentavos, 0);
        expect(sesion.estado, 'ABIERTA');
      },
    );

    test(
      'la lata inicial se arrastra del final de la última sesión cerrada',
      () async {
        final idAnterior = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 0,
        );
        await (db.update(
          db.sesionesDeCaja,
        )..where((s) => s.id.equals(idAnterior))).write(
          const SesionesDeCajaCompanion(
            estado: Value('CERRADA'),
            lataFinalCentavos: Value(45000),
          ),
        );

        await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
        final sesion = await sesionAbierta(db);
        expect(sesion!.lataInicialCentavos, 45000);
      },
    );

    test(
      'abrir con una sesión ya ABIERTA bloquea: tira SesionYaAbiertaException',
      () async {
        // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" —
        // ya no se une en silencio a la sesión existente (eso descartaba
        // los montos nuevos sin avisar); el segundo intento se entera de
        // que ya hay una abierta y no la toca.
        final primeraId = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 10000,
        );

        await expectLater(
          abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 99999),
          throwsA(isA<SesionYaAbiertaException>()),
        );

        final abiertas = await (db.select(
          db.sesionesDeCaja,
        )..where((s) => s.estado.equals('ABIERTA'))).get();
        expect(abiertas, hasLength(1));
        expect(abiertas.single.id, primeraId);
        expect(abiertas.single.fondoInicialCentavos, 10000);
      },
    );

    test(
      'SesionYaAbiertaException trae la sesión existente para avisar quién/cuándo',
      () async {
        await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 10000);

        try {
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
          fail('debía tirar SesionYaAbiertaException');
        } on SesionYaAbiertaException catch (e) {
          expect(e.sesion.usuarioAbrioId, usuarioId);
          expect(e.sesion.estado, 'ABIERTA');
        }
      },
    );
  });

  group('verificarSesionAbierta', () {
    test('sesión ABIERTA: no tira nada', () async {
      final id = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await verificarSesionAbierta(db, id);
    });

    test('sesión CERRADA: tira SesionCerradaException', () async {
      final id = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      await (db.update(
        db.sesionesDeCaja,
      )..where((s) => s.id.equals(id))).write(const SesionesDeCajaCompanion(estado: Value('CERRADA')));

      await expectLater(
        verificarSesionAbierta(db, id),
        throwsA(isA<SesionCerradaException>()),
      );
    });

    test('sesión inexistente: tira ArgumentError', () async {
      await expectLater(
        verificarSesionAbierta(db, 999999),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('lineaDesdeProducto', () {
    test('producto por unidad', () async {
      final id = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              precioCentavos: const Value(112000),
              costoCentavos: const Value(80000),
            ),
          );
      final producto = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();

      final linea =
          lineaDesdeProducto(producto, cantidad: 3) as LineaVentaPorUnidad;
      expect(linea.cantidad, 3);
      expect(linea.precioUnitarioCentavos, 112000);
      expect(linea.costoUnitarioCentavos, 80000);
    });

    test('producto pesable', () async {
      final id = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Jamón crudo',
              esPesable: const Value(true),
              precioPorKiloCentavos: const Value(300000),
              costoPorKiloCentavos: const Value(180000),
            ),
          );
      final producto = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();

      final linea =
          lineaDesdeProducto(producto, gramos: 350) as LineaVentaPesable;
      expect(linea.gramos, 350);
      expect(linea.subtotalCentavos, 105000);
    });

    test(
      '"Varios" usa el monto cargado a mano, no el precio del catálogo (que es null)',
      () async {
        final varios = await (db.select(
          db.productos,
        )..where((p) => p.esVarios.equals(true))).getSingle();

        final linea =
            lineaDesdeProducto(varios, cantidad: 1, montoVariosCentavos: 50000)
                as LineaVentaPorUnidad;
        expect(linea.precioUnitarioCentavos, 50000);
        expect(linea.esVarios, true);
        expect(linea.costoUnitarioCentavos, isNull);
      },
    );

    test('un cigarrillo tipo atado conserva su clasificación', () async {
      final id = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Marlboro',
              precioCentavos: const Value(500000),
              tipoCigarrillo: const Value('atado'),
            ),
          );
      final producto = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();

      final linea =
          lineaDesdeProducto(producto, cantidad: 1) as LineaVentaPorUnidad;
      expect(linea.tipoCigarrillo, TipoCigarrillo.atado);
    });
  });

  group('registrarVenta — persiste todo lo que toca una venta', () {
    late int sesionId;
    late int medioEfectivoId;
    late int medioVirtualId;
    late Producto cocaCola;

    setUp(() async {
      sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      final efectivo = await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(true))).getSingle();
      final virtual = await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(false))).getSingle();
      medioEfectivoId = efectivo.id;
      medioVirtualId = virtual.id;

      final id = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              precioCentavos: const Value(112000),
              costoCentavos: const Value(80000),
              stock: const Value(20),
            ),
          );
      cocaCola = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(id))).getSingle();
    });

    test('un pago negativo se rechaza y no graba nada (revisión 2026-10-03)', () async {
      final venta = Venta(lineas: [lineaDesdeProducto(cocaCola)]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.mixto,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
        pasoRedondeoCentavos: 10000,
      );
      await expectLater(
        registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos + 30000, esEfectivo: true),
            PagoARegistrar(medioPagoId: medioVirtualId, montoCentavos: -30000, esEfectivo: false),
          ],
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.ventas).get(), isEmpty);
      expect(await db.select(db.pagos).get(), isEmpty);
    });

    test(
      'venta simple en efectivo: descuenta stock y genera un movimiento de caja normal',
      () async {
        final linea = lineaDesdeProducto(cocaCola, cantidad: 2);
        final venta = Venta(lineas: [linea]);
        final resultado = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.efectivo,
          configRecargoCigarrillos: const ConfigRecargoCigarrillos(
            primerAtadoCentavos: 30000,
            atadoAdicionalCentavos: 10000,
          ),
          pasoRedondeoCentavos: 10000,
        );

        final (ventaId, _) = await registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(
              medioPagoId: medioEfectivoId,
              montoCentavos: resultado.totalCentavos,
              esEfectivo: true,
            ),
          ],
        );

        final filaVenta = await (db.select(
          db.ventas,
        )..where((v) => v.id.equals(ventaId))).getSingle();
        expect(filaVenta.totalCentavos, resultado.totalCentavos);

        final productoActualizado = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(cocaCola.id))).getSingle();
        expect(productoActualizado.stock, 18);

        final movimientosStock = await (db.select(
          db.movimientosDeStock,
        )..where((m) => m.ventaId.equals(ventaId))).get();
        expect(movimientosStock, hasLength(1));
        expect(movimientosStock.single.stockAnterior, 20);
        expect(movimientosStock.single.stockPosterior, 18);

        final movimientosCaja = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.ventaId.equals(ventaId))).get();
        expect(movimientosCaja, hasLength(1));
        final cajaNormal = await (db.select(
          db.cajas,
        )..where((c) => c.esLata.equals(false))).getSingle();
        expect(movimientosCaja.single.cajaId, cajaNormal.id);
        expect(movimientosCaja.single.montoCentavos, resultado.totalCentavos);
      },
    );

    test(
      'venta con descuento (Regla 17): guarda descuentoCentavos y cobra el total ya descontado',
      () async {
        final linea = lineaDesdeProducto(
          cocaCola,
          cantidad: 1,
        ); // subtotal 112000
        final venta = Venta(lineas: [linea]);
        final resultado = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: const ConfigRecargoCigarrillos(
            primerAtadoCentavos: 30000,
            atadoAdicionalCentavos: 10000,
          ),
          pasoRedondeoCentavos: 10000,
          tipoDescuento: TipoDescuento.porcentaje,
          valorDescuento: 1500, // 15%, Cliente Frecuente
        );
        expect(resultado.descuentoCentavos, 16800); // 15% de 112000
        expect(resultado.totalCentavos, 95200);

        final (ventaId, _) = await registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(
              medioPagoId: medioVirtualId,
              montoCentavos: resultado.totalCentavos,
              esEfectivo: false,
            ),
          ],
        );

        final filaVenta = await (db.select(
          db.ventas,
        )..where((v) => v.id.equals(ventaId))).getSingle();
        expect(filaVenta.descuentoCentavos, 16800);
        expect(filaVenta.totalCentavos, 95200);

        final movimientosCaja = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.ventaId.equals(ventaId))).get();
        // Virtual 100%: sin movimiento de caja física, igual que cualquier
        // venta 100% Mercado Pago — el descuento no cambia esa regla.
        expect(movimientosCaja, isEmpty);
      },
    );

    test(
      'venta pagada 100% por Mercado Pago: no genera movimiento de caja',
      () async {
        final linea = lineaDesdeProducto(cocaCola, cantidad: 1);
        final venta = Venta(lineas: [linea]);
        final resultado = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: const ConfigRecargoCigarrillos(
            primerAtadoCentavos: 30000,
            atadoAdicionalCentavos: 10000,
          ),
          pasoRedondeoCentavos: 10000,
        );

        final (ventaId, _) = await registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(
              medioPagoId: medioVirtualId,
              montoCentavos: resultado.totalCentavos,
              esEfectivo: false,
            ),
          ],
        );

        final movimientosCaja = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.ventaId.equals(ventaId))).get();
        expect(movimientosCaja, isEmpty);

        final pagos = await (db.select(
          db.pagos,
        )..where((p) => p.ventaId.equals(ventaId))).get();
        expect(pagos, hasLength(1));
        expect(pagos.single.montoCentavos, resultado.totalCentavos);
      },
    );

    test(
      'pago mixto: un movimiento de caja solo por la porción efectivo',
      () async {
        final linea = lineaDesdeProducto(cocaCola, cantidad: 1);
        final venta = Venta(lineas: [linea]);
        final resultado = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.mixto,
          configRecargoCigarrillos: const ConfigRecargoCigarrillos(
            primerAtadoCentavos: 30000,
            atadoAdicionalCentavos: 10000,
          ),
          pasoRedondeoCentavos: 10000,
        );

        final montoEfectivo = 50000;
        final montoVirtual = resultado.totalCentavos - montoEfectivo;

        final (ventaId, _) = await registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(
              medioPagoId: medioEfectivoId,
              montoCentavos: montoEfectivo,
              esEfectivo: true,
            ),
            PagoARegistrar(
              medioPagoId: medioVirtualId,
              montoCentavos: montoVirtual,
              esEfectivo: false,
            ),
          ],
        );

        final pagos = await (db.select(
          db.pagos,
        )..where((p) => p.ventaId.equals(ventaId))).get();
        expect(pagos, hasLength(2));

        final movimientosCaja = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.ventaId.equals(ventaId))).get();
        expect(movimientosCaja, hasLength(1));
        expect(movimientosCaja.single.montoCentavos, montoEfectivo);
      },
    );

    test('"Varios" no genera movimiento de stock', () async {
      final varios = await (db.select(
        db.productos,
      )..where((p) => p.esVarios.equals(true))).getSingle();
      final linea = lineaDesdeProducto(
        varios,
        cantidad: 1,
        montoVariosCentavos: 30000,
      );
      final venta = Venta(lineas: [linea]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(
          primerAtadoCentavos: 30000,
          atadoAdicionalCentavos: 10000,
        ),
        pasoRedondeoCentavos: 10000,
      );

      final (ventaId, _) = await registrarVenta(
        db,
        venta: venta,
        resultado: resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [
          PagoARegistrar(
            medioPagoId: medioEfectivoId,
            montoCentavos: resultado.totalCentavos,
            esEfectivo: true,
          ),
        ],
      );

      final movimientosStock = await (db.select(
        db.movimientosDeStock,
      )..where((m) => m.ventaId.equals(ventaId))).get();
      expect(movimientosStock, isEmpty);
    });

    test('el stock puede quedar negativo: se vende igual (Regla 8)', () async {
      final linea = lineaDesdeProducto(
        cocaCola,
        cantidad: 50,
      ); // hay 20 en stock
      final venta = Venta(lineas: [linea]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(
          primerAtadoCentavos: 30000,
          atadoAdicionalCentavos: 10000,
        ),
        pasoRedondeoCentavos: 10000,
      );

      await registrarVenta(
        db,
        venta: venta,
        resultado: resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [
          PagoARegistrar(
            medioPagoId: medioEfectivoId,
            montoCentavos: resultado.totalCentavos,
            esEfectivo: true,
          ),
        ],
      );

      final productoActualizado = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(cocaCola.id))).getSingle();
      expect(productoActualizado.stock, -30);
    });
  });

  group(
    'calcularResultadoVenta / pagosSegunMedio / registrarVentaSegunMedio — '
    'pegamento compartido entre el servidor HTTP y el puerto local (Regla 3)',
    () {
      late int sesionId;
      late int medioEfectivoId;
      late int medioVirtualId;
      late Producto cocaCola;

      setUp(() async {
        sesionId = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 0,
        );
        final efectivo = await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(true))).getSingle();
        final virtual = await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(false))).getSingle();
        medioEfectivoId = efectivo.id;
        medioVirtualId = virtual.id;

        final id = await db.into(db.productos).insert(
              ProductosCompanion.insert(
                nombre: 'Coca-Cola',
                precioCentavos: const Value(112000),
                costoCentavos: const Value(80000),
                stock: const Value(20),
              ),
            );
        cocaCola = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(id))).getSingle();
      });

      test('calcularResultadoVenta usa la configuración real de la base (sin pasar una propia)', () async {
        final linea = lineaDesdeProducto(cocaCola, cantidad: 1);
        final resultado = await calcularResultadoVenta(
          db,
          lineas: [linea],
          medio: ComposicionPago.efectivo,
        );
        // $1.120 redondea hacia arriba al paso de $100 sembrado por default
        // (Regla 2) — efectivo siempre redondea.
        expect(resultado.totalCentavos, 120000);
      });

      test('pagosSegunMedio efectivo: un solo pago contra el medio efectivo', () async {
        final pagos = await pagosSegunMedio(
          db,
          medio: ComposicionPago.efectivo,
          totalCentavos: 112000,
        );
        expect(pagos, hasLength(1));
        expect(pagos.single.medioPagoId, medioEfectivoId);
        expect(pagos.single.esEfectivo, true);
        expect(pagos.single.montoCentavos, 112000);
      });

      test('pagosSegunMedio virtual: un solo pago contra el medio virtual, con canal', () async {
        final pagos = await pagosSegunMedio(
          db,
          medio: ComposicionPago.virtual,
          totalCentavos: 112000,
          canal: 'qr',
        );
        expect(pagos, hasLength(1));
        expect(pagos.single.medioPagoId, medioVirtualId);
        expect(pagos.single.esEfectivo, false);
        expect(pagos.single.canal, 'qr');
      });

      test('pagosSegunMedio mixto: reparte entre efectivo y virtual sin perder un centavo', () async {
        final pagos = await pagosSegunMedio(
          db,
          medio: ComposicionPago.mixto,
          totalCentavos: 112000,
          montoEfectivoMixtoCentavos: 50000,
        );
        expect(pagos, hasLength(2));
        final efectivo = pagos.firstWhere((p) => p.esEfectivo);
        final virtual = pagos.firstWhere((p) => !p.esEfectivo);
        expect(efectivo.montoCentavos, 50000);
        expect(virtual.montoCentavos, 62000);
        expect(efectivo.montoCentavos + virtual.montoCentavos, 112000);
      });

      test('registrarVentaSegunMedio calcula, arma los pagos y graba todo junto', () async {
        final linea = lineaDesdeProducto(cocaCola, cantidad: 2);
        final resultado = await registrarVentaSegunMedio(
          db,
          lineas: [linea],
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
        );

        // $2.240 redondea hacia arriba a $2.300 (paso de $100, Regla 2).
        expect(resultado.totalCentavos, 230000);

        final ventaGuardada = await (db.select(
          db.ventas,
        )..where((v) => v.id.equals(resultado.ventaId))).getSingle();
        expect(ventaGuardada.totalCentavos, 230000);

        final pagosGuardados = await (db.select(
          db.pagos,
        )..where((p) => p.ventaId.equals(resultado.ventaId))).get();
        expect(pagosGuardados, hasLength(1));
        expect(pagosGuardados.single.medioPagoId, medioEfectivoId);

        final productoActualizado = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(cocaCola.id))).getSingle();
        expect(productoActualizado.stock, 18); // 20 - 2
      });
    },
  );

  group('productosMasVendidosIds (rediseño de venta 2026-09-25, tercera pasada)', () {
    late int sesionId;
    late int medioEfectivoId;
    late int cocaColaId;
    late int aguaId;
    late int fernetId;

    setUp(() async {
      sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final efectivo = await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(true))).getSingle();
      medioEfectivoId = efectivo.id;

      cocaColaId = await db
          .into(db.productos)
          .insert(ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: const Value(50)));
      aguaId = await db
          .into(db.productos)
          .insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(80000), stock: const Value(50)));
      fernetId = await db
          .into(db.productos)
          .insert(ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(500000), stock: const Value(50)));
    });

    Future<int> venderUnidad(int productoId) async {
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
      final venta = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(
          primerAtadoCentavos: 30000,
          atadoAdicionalCentavos: 10000,
        ),
        pasoRedondeoCentavos: 10000,
      );
      final (ventaId, _) = await registrarVenta(
        db,
        venta: venta,
        resultado: resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [
          PagoARegistrar(
            medioPagoId: medioEfectivoId,
            montoCentavos: resultado.totalCentavos,
            esEfectivo: true,
          ),
        ],
      );
      return ventaId;
    }

    test('ordena por cantidad de líneas de venta, más vendido primero', () async {
      await venderUnidad(cocaColaId);
      await venderUnidad(cocaColaId);
      await venderUnidad(cocaColaId);
      await venderUnidad(aguaId);
      await venderUnidad(aguaId);
      await venderUnidad(fernetId);

      final ids = await productosMasVendidosIds(db);
      expect(ids, [cocaColaId, aguaId, fernetId]);
    });

    test('una venta anulada no cuenta (Regla 6: no fue una venta real)', () async {
      await venderUnidad(cocaColaId);
      final ventaAnulada = await venderUnidad(fernetId);
      await venderUnidad(fernetId);
      await anularVenta(db, ventaId: ventaAnulada, usuarioId: usuarioId, motivo: 'prueba');

      final ids = await productosMasVendidosIds(db);
      // Fernet se vendió 2 veces pero una fue anulada: queda 1, empatado con
      // Coca-Cola — el orden entre empatados no importa acá, alcanza con que
      // los dos estén y Fernet no aparezca dos veces.
      expect(ids, containsAll([cocaColaId, fernetId]));
      expect(ids, hasLength(2));
    });

    test('respeta el límite', () async {
      await venderUnidad(cocaColaId);
      await venderUnidad(aguaId);
      await venderUnidad(fernetId);

      final ids = await productosMasVendidosIds(db, limite: 2);
      expect(ids, hasLength(2));
    });
  });

  group('registrarVenta contra una caja ya cerrada (Fase 0.1)', () {
    test('tira SesionCerradaException y no graba venta, líneas ni caja', () async {
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      final medio = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
      await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId)))
          .write(const SesionesDeCajaCompanion(estado: Value('CERRADA')));

      final venta = Venta(lineas: [
        LineaVentaPorUnidad(
          productoId: '1',
          nombreProducto: 'Algo',
          proveedorId: null,
          cantidad: 1,
          precioUnitarioCentavos: 100000,
          costoUnitarioCentavos: null,
        ),
      ]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 0, atadoAdicionalCentavos: 0),
        pasoRedondeoCentavos: 10000,
      );

      await expectLater(
        registrarVenta(
          db,
          venta: venta,
          resultado: resultado,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [PagoARegistrar(medioPagoId: medio.id, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
        ),
        throwsA(isA<SesionCerradaException>()),
      );
      expect(await db.select(db.ventas).get(), isEmpty);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });
  });
}
