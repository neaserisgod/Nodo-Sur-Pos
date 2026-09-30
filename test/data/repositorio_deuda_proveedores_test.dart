import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import '../helpers/base_para_tests.dart';

/// Cuenta corriente con proveedores (El dueño, 2026-09-29): el saldo es cargos
/// menos pagos, y un pago que sale de una caja baja el arqueo y queda con
/// dueño.
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int proveedorId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 1000000, mpInicialCentavos: 500000);
    proveedorId = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'ZM', nombre: 'Fiambrería test'));
  });
  tearDown(() => db.close());

  Future<void> cargar(int monto) =>
      cargarDeuda(db, proveedorId: proveedorId, montoCentavos: monto, fecha: DateTime(2026, 9, 20), nota: 'Remito 123', usuarioId: usuarioId)
          .then((_) {});

  test('el saldo es la suma de cargos menos la de pagos', () async {
    await cargar(300000);
    await cargar(200000);
    await pagarDeuda(db, proveedorId: proveedorId, montoCentavos: 150000, origen: OrigenPagoDeuda.fuera, usuarioId: usuarioId);
    expect(await saldoDeuda(db, proveedorId), 350000);
    expect((await saldosDeuda(db))[proveedorId], 350000);
  });

  test('no se puede pagar más que la deuda ni cargar un monto no positivo', () async {
    await cargar(100000);
    await expectLater(
      pagarDeuda(db, proveedorId: proveedorId, montoCentavos: 100001, origen: OrigenPagoDeuda.fuera, usuarioId: usuarioId),
      throwsArgumentError,
    );
    await expectLater(cargarDeuda(db, proveedorId: proveedorId, montoCentavos: 0, fecha: DateTime.now(), usuarioId: usuarioId), throwsArgumentError);
  });

  test('pagar del cajón baja el efectivo esperado y deja el movimiento con dueño', () async {
    await cargar(300000);
    final antes = (await estadoCajaEnVivo(db, sesionId)).efectivoEsperadoCentavos;
    await pagarDeuda(
      db,
      proveedorId: proveedorId,
      montoCentavos: 120000,
      origen: OrigenPagoDeuda.cajon,
      usuarioId: usuarioId,
      sesionCajaId: sesionId,
    );
    final despues = await estadoCajaEnVivo(db, sesionId);
    expect(despues.efectivoEsperadoCentavos, antes - 120000);

    final mov = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).getSingle();
    expect(mov.proveedorId, proveedorId);
    expect(mov.montoCentavos, 120000);
    expect(mov.nota, contains('Fiambrería test'));
  });

  test('pagar por Mercado Pago baja el MP esperado y no el cajón', () async {
    await cargar(300000);
    final antes = await estadoCajaEnVivo(db, sesionId);
    await pagarDeuda(
      db,
      proveedorId: proveedorId,
      montoCentavos: 100000,
      origen: OrigenPagoDeuda.mp,
      usuarioId: usuarioId,
      sesionCajaId: sesionId,
    );
    final despues = await estadoCajaEnVivo(db, sesionId);
    expect(despues.mpEsperadoCentavos, antes.mpEsperadoCentavos - 100000);
    expect(despues.efectivoEsperadoCentavos, antes.efectivoEsperadoCentavos);
  });

  test('pagar "fuera de la caja" no toca ninguna caja', () async {
    await cargar(300000);
    final antes = await estadoCajaEnVivo(db, sesionId);
    await pagarDeuda(db, proveedorId: proveedorId, montoCentavos: 100000, origen: OrigenPagoDeuda.fuera, usuarioId: usuarioId);
    final despues = await estadoCajaEnVivo(db, sesionId);
    expect(despues.efectivoEsperadoCentavos, antes.efectivoEsperadoCentavos);
    expect(despues.mpEsperadoCentavos, antes.mpEsperadoCentavos);
    expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
  });

  test('un pago desde una caja sin sesión abierta se rechaza', () async {
    await cargar(300000);
    await expectLater(
      pagarDeuda(db, proveedorId: proveedorId, montoCentavos: 1000, origen: OrigenPagoDeuda.cajon, usuarioId: usuarioId),
      throwsA(isA<SinCajaAbiertaException>()),
    );
    expect(await saldoDeuda(db, proveedorId), 300000);
  });

  test('anular un pago devuelve la deuda y revierte el movimiento de caja', () async {
    await cargar(300000);
    final antes = (await estadoCajaEnVivo(db, sesionId)).efectivoEsperadoCentavos;
    final pagoId = await pagarDeuda(
      db,
      proveedorId: proveedorId,
      montoCentavos: 120000,
      origen: OrigenPagoDeuda.cajon,
      usuarioId: usuarioId,
      sesionCajaId: sesionId,
    );
    await anularMovimientoDeuda(db, movimientoId: pagoId, usuarioId: usuarioId, sesionCajaId: sesionId);
    expect(await saldoDeuda(db, proveedorId), 300000);
    expect((await estadoCajaEnVivo(db, sesionId)).efectivoEsperadoCentavos, antes);
    // El rastro queda: dos movimientos de caja (el pago y su reversión).
    expect(await db.select(db.movimientosDeCaja).get(), hasLength(2));
  });

  test('no se anula un cargo si hay pagos que dependen de él', () async {
    await cargar(100000);
    await pagarDeuda(db, proveedorId: proveedorId, montoCentavos: 100000, origen: OrigenPagoDeuda.fuera, usuarioId: usuarioId);
    final cargo = (await listarMovimientosDeuda(db, proveedorId)).firstWhere((m) => m.tipo == 'CARGO');
    await expectLater(
      anularMovimientoDeuda(db, movimientoId: cargo.id, usuarioId: usuarioId),
      throwsArgumentError,
    );
  });

  test('la lata paga desde su caja: baja lo esperado de la lata, no el cajón', () async {
    await cargar(300000);
    await pagarDeuda(
      db,
      proveedorId: proveedorId,
      montoCentavos: 50000,
      origen: OrigenPagoDeuda.lata,
      usuarioId: usuarioId,
      sesionCajaId: sesionId,
    );
    expect(await pagosALataDelDia(db, sesionId), 50000);
    expect(await gastosEnEfectivoDelDia(db, sesionId), 0);
  });
}
