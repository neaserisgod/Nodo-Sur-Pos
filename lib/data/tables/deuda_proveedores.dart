import 'package:drift/drift.dart';

import 'caja.dart';
import 'catalogo.dart';
import 'usuarios.dart';

/// Cuenta corriente con cada proveedor: lo que el dueño LE DEBE (El dueño,
/// 2026-09-29: "un apartado de deuda o cuenta corriente para ir cargando los
/// saldos que yo adeudo, y pagar desde ahí dejando registro, en lugar de
/// gastos registrados pero sin dueño").
///
/// Es un libro aparte de la reposición/separación (`proveedores.separado*`):
/// no se toca una con la otra (El dueño: "de momento no puedo separar"). El
/// saldo es la suma de cargos menos la suma de pagos, sin anulados — nunca
/// se guarda un número que pueda desalinearse del libro.
///
/// Un PAGO que sale de una caja (cajón, Mercado Pago o lata) genera además un
/// `MovimientoCaja` tipo PAGO_PROVEEDOR con el `proveedorId` puesto — así el
/// arqueo baja lo que salió y el gasto tiene dueño. Local de cada
/// dispositivo: no se sincroniza.
@DataClassName('MovimientoDeuda')
class MovimientosDeuda extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get proveedorId => integer().references(Proveedores, #id)();

  /// 'CARGO' (le debo más) | 'PAGO' (le pagué).
  TextColumn get tipo => text()();
  IntColumn get montoCentavos => integer()();

  /// De cuándo es la deuda (cargo) o cuándo se pagó (pago). Lo elige quien
  /// carga: la mercadería puede haber llegado antes de anotarla.
  DateTimeColumn get fecha => dateTime()();

  /// Remito, factura o lo que ayude a reconocerla.
  TextColumn get nota => text().nullable()();

  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  /// 'cajon' | 'mp' | 'lata' | 'fuera' — solo en pagos. 'fuera' es plata
  /// que no pasó por ninguna caja de la app (transferencia desde otra cuenta).
  TextColumn get origenPago => text().nullable()();

  /// El movimiento de caja que generó este pago (null si salió 'fuera').
  IntColumn get movimientoCajaId => integer().nullable().references(MovimientosDeCaja, #id)();

  /// Anulado = deja de contar en el saldo, pero la fila queda (Regla 6:
  /// todo deja rastro).
  DateTimeColumn get anuladoEn => dateTime().nullable()();

  DateTimeColumn get creadoEn => dateTime().withDefault(currentDateAndTime)();
}
