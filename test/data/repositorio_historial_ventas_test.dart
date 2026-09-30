import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_historial_ventas.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int medioEfectivoId;
  late int medioMpId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioMpId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
  });
  tearDown(() => db.close());

  /// Venta con una sola línea y un solo pago, a la fecha/canal que se pida
  /// — sin pasar por sesión de caja ni stock, que acá no hacen falta.
  Future<int> crearVenta({
    required DateTime fecha,
    required int totalCentavos,
    required int medioPagoId,
    String? canal,
    String nombreProducto = 'Coca-Cola 500ml',
    int cantidad = 1,
  }) async {
    // Una sola sesión para todas las ventas fabricadas de este archivo (no
    // les importa a qué sesión queden atadas) — desde que `abrirSesion`
    // bloquea en vez de unirse en silencio (El dueño, 2026-09-19), un segundo
    // llamado con una ya abierta tira, así que se reusa la existente.
    final sesionId = (await sesionAbierta(db))?.id ??
        await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final ventaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        fecha: Value(fecha),
        subtotalCentavos: totalCentavos,
        totalCentavos: totalCentavos,
      ),
    );
    await db.into(db.lineasDeVenta).insert(
      LineasDeVentaCompanion.insert(
        ventaId: ventaId,
        nombreProductoFoto: nombreProducto,
        cantidad: Value(cantidad),
        precioUnitarioCentavos: totalCentavos ~/ cantidad,
      ),
    );
    await db.into(db.pagos).insert(
      PagosCompanion.insert(
        ventaId: ventaId,
        medioPagoId: medioPagoId,
        montoCentavos: totalCentavos,
        canal: Value(canal),
      ),
    );
    return ventaId;
  }

  test('solo trae ventas dentro del rango [desde, hasta)', () async {
    await crearVenta(fecha: DateTime(2026, 8, 1), totalCentavos: 10000, medioPagoId: medioEfectivoId);
    await crearVenta(fecha: DateTime(2026, 8, 15, 12), totalCentavos: 20000, medioPagoId: medioEfectivoId);
    await crearVenta(fecha: DateTime(2026, 8, 20), totalCentavos: 30000, medioPagoId: medioEfectivoId);

    final resultado = await historialDeVentas(
      db,
      desde: DateTime(2026, 8, 15),
      hasta: DateTime(2026, 8, 20),
    );

    expect(resultado, hasLength(1));
    expect(resultado.single.totalCentavos, 20000);
  });

  test('clasifica el medio: efectivo, QR, débito y mixto', () async {
    await crearVenta(fecha: DateTime(2026, 8, 15), totalCentavos: 10000, medioPagoId: medioEfectivoId);
    await crearVenta(fecha: DateTime(2026, 8, 15), totalCentavos: 20000, medioPagoId: medioMpId, canal: 'qr');
    await crearVenta(
      fecha: DateTime(2026, 8, 15),
      totalCentavos: 30000,
      medioPagoId: medioMpId,
      canal: 'debit_card',
    );
    // Mixto: dos pagos para la misma venta — reusa la sesión que ya abrió
    // `crearVenta` arriba.
    final sesionId = (await sesionAbierta(db))!.id;
    final ventaMixtaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        fecha: Value(DateTime(2026, 8, 15)),
        subtotalCentavos: 40000,
        totalCentavos: 40000,
      ),
    );
    await db.into(db.lineasDeVenta).insert(
      LineasDeVentaCompanion.insert(
        ventaId: ventaMixtaId,
        nombreProductoFoto: 'Fernet',
        cantidad: const Value(1),
        precioUnitarioCentavos: 40000,
      ),
    );
    await db.into(db.pagos).insert(
      PagosCompanion.insert(ventaId: ventaMixtaId, medioPagoId: medioEfectivoId, montoCentavos: 15000),
    );
    await db.into(db.pagos).insert(
      PagosCompanion.insert(ventaId: ventaMixtaId, medioPagoId: medioMpId, montoCentavos: 25000, canal: const Value('qr')),
    );

    final resultado = await historialDeVentas(
      db,
      desde: DateTime(2026, 8, 15),
      hasta: DateTime(2026, 8, 16),
    );

    final porMonto = {for (final v in resultado) v.totalCentavos: v.medio};
    expect(porMonto[10000], MedioVentaHistorial.efectivo);
    expect(porMonto[20000], MedioVentaHistorial.qr);
    expect(porMonto[30000], MedioVentaHistorial.debitCard);
    expect(porMonto[40000], MedioVentaHistorial.mixto);
  });

  test('filtroMedio deja solo las ventas de ese medio', () async {
    await crearVenta(fecha: DateTime(2026, 8, 15), totalCentavos: 10000, medioPagoId: medioEfectivoId);
    await crearVenta(fecha: DateTime(2026, 8, 15), totalCentavos: 20000, medioPagoId: medioMpId, canal: 'qr');

    final resultado = await historialDeVentas(
      db,
      desde: DateTime(2026, 8, 15),
      hasta: DateTime(2026, 8, 16),
      filtroMedio: MedioVentaHistorial.qr,
    );

    expect(resultado, hasLength(1));
    expect(resultado.single.totalCentavos, 20000);
  });

  test('el detalle lista cada producto con su cantidad', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final ventaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        fecha: Value(DateTime(2026, 8, 15)),
        subtotalCentavos: 30000,
        totalCentavos: 30000,
      ),
    );
    await db.into(db.lineasDeVenta).insert(
      LineasDeVentaCompanion.insert(
        ventaId: ventaId,
        nombreProductoFoto: 'Coca-Cola 500ml',
        cantidad: const Value(2),
        precioUnitarioCentavos: 10000,
      ),
    );
    await db.into(db.lineasDeVenta).insert(
      LineasDeVentaCompanion.insert(
        ventaId: ventaId,
        nombreProductoFoto: 'Fernet',
        cantidad: const Value(1),
        precioUnitarioCentavos: 10000,
      ),
    );
    await db.into(db.pagos).insert(
      PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: 30000),
    );

    final resultado = await historialDeVentas(db, desde: DateTime(2026, 8, 15), hasta: DateTime(2026, 8, 16));

    expect(resultado.single.detalle, 'Coca-Cola 500ml x2, Fernet x1');
  });
}
