import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int usuarioEditorId;
  late int sesionId;
  late int medioEfectivoId;
  late int medioVirtualId;
  late Producto cocaCola;
  late Producto fernet;

  const configRecargo = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    usuarioEditorId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ayuda finde'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioVirtualId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;

    final idCoca = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: const Value(20)),
        );
    cocaCola = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
    final idFernet = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(900000), stock: const Value(10)),
        );
    fernet = await (db.select(db.productos)..where((p) => p.id.equals(idFernet))).getSingle();
  });
  tearDown(() => db.close());

  Future<int> ventaOriginalCoca2Efectivo() async {
    final linea = lineaDesdeProducto(cocaCola, cantidad: 2);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: configRecargo,
      pasoRedondeoCentavos: 10000,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );
    return ventaId;
  }

  group('editarVenta — cambiar cantidad', () {
    test('repone el stock viejo y descuenta el nuevo, sin borrar el rastro del movimiento original', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      final stockTrasVentaOriginal =
          (await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle()).stock;
      expect(stockTrasVentaOriginal, 18); // 20 - 2

      final lineaNueva = lineaDesdeProducto(cocaCola, cantidad: 5);
      final ventaNueva = Venta(lineas: [lineaNueva]);
      final resultadoNuevo = calcularTotalVenta(
        venta: ventaNueva,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

      await editarVenta(
        db,
        ventaId: ventaId,
        ventaNueva: ventaNueva,
        resultadoNuevo: resultadoNuevo,
        pagosNuevos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoNuevo.totalCentavos, esEfectivo: true),
        ],
        usuarioId: usuarioEditorId,
        motivo: 'Error de tipeo, eran 5 no 2',
      );

      final productoFinal =
          await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle();
      expect(productoFinal.stock, 15); // 20 - 5, no 20-2-5

      // El movimiento original de la venta sigue existiendo (Regla 6: nunca se borra).
      final movimientosStock = await (db.select(db.movimientosDeStock)
            ..where((m) => m.ventaId.equals(ventaId)))
          .get();
      expect(movimientosStock.length, greaterThanOrEqualTo(3)); // original + reversión + reaplicación
      expect(movimientosStock.first.stockAnterior, 20);
      expect(movimientosStock.first.stockPosterior, 18); // el original, intacto
    });

    test('actualiza el total de la venta y deja el rastro de quién y cuándo editó (Regla 9)', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();

      final lineaNueva = lineaDesdeProducto(cocaCola, cantidad: 5);
      final ventaNueva = Venta(lineas: [lineaNueva]);
      final resultadoNuevo = calcularTotalVenta(
        venta: ventaNueva,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

      await editarVenta(
        db,
        ventaId: ventaId,
        ventaNueva: ventaNueva,
        resultadoNuevo: resultadoNuevo,
        pagosNuevos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoNuevo.totalCentavos, esEfectivo: true),
        ],
        usuarioId: usuarioEditorId,
        motivo: 'Error de tipeo, eran 5 no 2',
      );

      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.totalCentavos, resultadoNuevo.totalCentavos);
      expect(venta.editadaPorId, usuarioEditorId);
      expect(venta.editadaEn, isNotNull);
      expect(venta.motivoEdicion, 'Error de tipeo, eran 5 no 2');

      final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
      expect(lineas, hasLength(1));
      expect(lineas.single.cantidad, 5);
    });
  });

  group('editarVenta — cambiar medio de pago', () {
    test('de efectivo a virtual: revierte el movimiento de caja viejo y no genera uno nuevo', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      final linea = lineaDesdeProducto(cocaCola, cantidad: 2);
      final venta = Venta(lineas: [linea]);
      final resultado = calcularTotalVenta(
        venta: venta,
        composicionPago: ComposicionPago.virtual,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

      await editarVenta(
        db,
        ventaId: ventaId,
        ventaNueva: venta,
        resultadoNuevo: resultado,
        pagosNuevos: [
          PagoARegistrar(medioPagoId: medioVirtualId, montoCentavos: resultado.totalCentavos, esEfectivo: false),
        ],
        usuarioId: usuarioEditorId,
        motivo: 'Pagó QR, no efectivo',
      );

      final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.ventaId.equals(ventaId))).get();
      final suma = movimientos.fold<int>(0, (acc, m) => acc + m.montoCentavos);
      expect(suma, 0); // el original + la reversión se cancelan, y no hay reaplicación (es virtual)

      final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();
      expect(pagos.single.medioPagoId, medioVirtualId);
    });
  });

  group('editarVenta — agregar y quitar líneas', () {
    test('agregar una línea nueva descuenta stock de ese producto', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();

      final ventaNueva = Venta(lineas: [
        lineaDesdeProducto(cocaCola, cantidad: 2),
        lineaDesdeProducto(fernet, cantidad: 1),
      ]);
      final resultadoNuevo = calcularTotalVenta(
        venta: ventaNueva,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

      await editarVenta(
        db,
        ventaId: ventaId,
        ventaNueva: ventaNueva,
        resultadoNuevo: resultadoNuevo,
        pagosNuevos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoNuevo.totalCentavos, esEfectivo: true),
        ],
        usuarioId: usuarioEditorId,
        motivo: 'Se había olvidado el fernet',
      );

      final fernetFinal = await (db.select(db.productos)..where((p) => p.id.equals(fernet.id))).getSingle();
      expect(fernetFinal.stock, 9); // 10 - 1
    });

    test('quitar una línea repone su stock por completo', () async {
      final linea1 = lineaDesdeProducto(cocaCola, cantidad: 2);
      final linea2 = lineaDesdeProducto(fernet, cantidad: 1);
      final ventaOriginal = Venta(lineas: [linea1, linea2]);
      final resultadoOriginal = calcularTotalVenta(
        venta: ventaOriginal,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );
      final (ventaId, _) = await registrarVenta(
        db,
        venta: ventaOriginal,
        resultado: resultadoOriginal,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoOriginal.totalCentavos, esEfectivo: true),
        ],
      );

      final ventaNueva = Venta(lineas: [lineaDesdeProducto(cocaCola, cantidad: 2)]);
      final resultadoNuevo = calcularTotalVenta(
        venta: ventaNueva,
        composicionPago: ComposicionPago.efectivo,
        configRecargoCigarrillos: configRecargo,
        pasoRedondeoCentavos: 10000,
      );

      await editarVenta(
        db,
        ventaId: ventaId,
        ventaNueva: ventaNueva,
        resultadoNuevo: resultadoNuevo,
        pagosNuevos: [
          PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoNuevo.totalCentavos, esEfectivo: true),
        ],
        usuarioId: usuarioEditorId,
        motivo: 'El fernet no era de esta venta',
      );

      final fernetFinal = await (db.select(db.productos)..where((p) => p.id.equals(fernet.id))).getSingle();
      expect(fernetFinal.stock, 10); // vuelve al stock original completo
    });
  });

  group('anularVenta', () {
    test('revierte stock y caja, y marca la venta como anulada sin borrar líneas ni pagos', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      final stockTrasVenta =
          (await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle()).stock;
      expect(stockTrasVenta, 18); // 20 - 2

      await anularVenta(
        db,
        ventaId: ventaId,
        usuarioId: usuarioEditorId,
        motivo: 'El cliente se arrepintió',
      );

      final productoFinal =
          await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle();
      expect(productoFinal.stock, 20); // repuesto por completo

      final movimientosCaja = await (db.select(db.movimientosDeCaja)..where((m) => m.ventaId.equals(ventaId))).get();
      final suma = movimientosCaja.fold<int>(0, (acc, m) => acc + m.montoCentavos);
      expect(suma, 0); // el original + la reversión se cancelan

      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.anuladaPorId, usuarioEditorId);
      expect(venta.anuladaEn, isNotNull);
      expect(venta.motivoAnulacion, 'El cliente se arrepintió');

      // A diferencia de editar, anular NO borra el detalle (Regla 6: se ve
      // que existió, no desaparece).
      final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
      expect(lineas, hasLength(1));
      final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();
      expect(pagos, hasLength(1));
    });

    test('no deja anular una venta de una sesión ya cerrada', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );

      expect(
        () => anularVenta(db, ventaId: ventaId, usuarioId: usuarioEditorId, motivo: 'Tarde'),
        throwsArgumentError,
      );

      // El stock no se tocó — la anulación se frenó antes de tocar nada.
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle();
      expect(producto.stock, 18);
    });

    test('no deja anular dos veces la misma venta', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      await anularVenta(db, ventaId: ventaId, usuarioId: usuarioEditorId, motivo: 'Primera anulación');

      expect(
        () => anularVenta(db, ventaId: ventaId, usuarioId: usuarioEditorId, motivo: 'Segunda'),
        throwsArgumentError,
      );
    });

    test(
      'no deja editar una venta ya anulada (evitaría revertir y reaplicar stock/caja dos veces)',
      () async {
        final ventaId = await ventaOriginalCoca2Efectivo();
        await anularVenta(db, ventaId: ventaId, usuarioId: usuarioEditorId, motivo: 'Se arrepintió');

        final lineaNueva = lineaDesdeProducto(cocaCola, cantidad: 1);
        final ventaNueva = Venta(lineas: [lineaNueva]);
        final resultadoNuevo = calcularTotalVenta(
          venta: ventaNueva,
          composicionPago: ComposicionPago.efectivo,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: 10000,
        );

        expect(
          () => editarVenta(
            db,
            ventaId: ventaId,
            ventaNueva: ventaNueva,
            resultadoNuevo: resultadoNuevo,
            pagosNuevos: [
              PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultadoNuevo.totalCentavos, esEfectivo: true),
            ],
            usuarioId: usuarioEditorId,
            motivo: 'Intento de edición',
          ),
          throwsArgumentError,
        );

        // Nada se tocó de nuevo: el stock quedó como lo dejó la anulación
        // (repuesto por completo), no de vuelta descontado por una edición
        // que no debería haber corrido.
        final producto = await (db.select(db.productos)..where((p) => p.id.equals(cocaCola.id))).getSingle();
        expect(producto.stock, 20);
      },
    );
  });

  group('lineaVentaDesdeFila', () {
    test('una línea con producto real se reconstruye tal cual', () async {
      final ventaId = await ventaOriginalCoca2Efectivo();
      final fila = (await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get()).single;

      final linea = lineaVentaDesdeFila(fila, productoVariosId: 999);

      expect(linea.productoId, cocaCola.id.toString());
      expect(linea.esVarios, isFalse);
      expect((linea as LineaVentaPorUnidad).cantidad, 2);
    });

    test('una línea sin producto (carga histórica) se reconstruye como Varios, sin perder el detalle', () async {
      final varios = await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Varios', esVarios: const Value(true)),
          );
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 5000, totalCentavos: 5000),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Fiambre 300g',
              precioUnitarioCentavos: 5000,
            ),
          );
      final fila = (await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get()).single;

      final linea = lineaVentaDesdeFila(fila, productoVariosId: varios);

      expect(linea.productoId, varios.toString());
      expect(linea.esVarios, isTrue);
      expect(linea.nombreProducto, 'Fiambre 300g');
    });
  });

  test('editar una venta con descuento conserva el descuento y el canal (revisión 2026-09-29)', () async {
    final linea = lineaDesdeProducto(cocaCola, cantidad: 10);
    final v = Venta(lineas: [linea]);
    final r = calcularTotalVenta(
      venta: v,
      composicionPago: ComposicionPago.virtual,
      configRecargoCigarrillos: configRecargo,
      pasoRedondeoCentavos: 10000,
      tipoDescuento: TipoDescuento.porcentaje,
      valorDescuento: 1500,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: v,
      resultado: r,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioVirtualId, montoCentavos: r.totalCentavos, esEfectivo: false, canal: 'qr')],
    );
    // Mismo cálculo que hace el editor: el descuento original como monto fijo.
    final r2 = calcularTotalVenta(
      venta: v,
      composicionPago: ComposicionPago.virtual,
      configRecargoCigarrillos: configRecargo,
      pasoRedondeoCentavos: 10000,
      tipoDescuento: TipoDescuento.monto,
      valorDescuento: r.descuentoCentavos,
    );
    await editarVenta(
      db,
      ventaId: ventaId,
      ventaNueva: v,
      resultadoNuevo: r2,
      pagosNuevos: [PagoARegistrar(medioPagoId: medioVirtualId, montoCentavos: r2.totalCentavos, esEfectivo: false, canal: 'qr')],
      usuarioId: usuarioEditorId,
      motivo: 'x',
    );
    final fila = await (db.select(db.ventas)..where((x) => x.id.equals(ventaId))).getSingle();
    expect(fila.descuentoCentavos, r.descuentoCentavos);
    expect(fila.totalCentavos, r.totalCentavos);
    final pago = await (db.select(db.pagos)..where((x) => x.ventaId.equals(ventaId))).getSingle();
    expect(pago.canal, 'qr');
  });
}
