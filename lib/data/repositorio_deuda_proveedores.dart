// Cuenta corriente con los proveedores (lo que el dueño les debe). Ver el
// comentario de la tabla `movimientos_deuda`.

import 'package:drift/drift.dart';

import 'database.dart';
import 'identidad_sync.dart';

/// De dónde sale la plata de un pago. Las tres primeras mueven una caja de
/// la app y dejan un movimiento de caja con dueño; 'fuera' no.
enum OrigenPagoDeuda {
  cajon('cajon', 'Del cajón'),
  mp('mp', 'Mercado Pago'),
  lata('lata', 'De la lata'),
  fuera('fuera', 'Fuera de la caja');

  const OrigenPagoDeuda(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static OrigenPagoDeuda desde(String? clave) =>
      OrigenPagoDeuda.values.firstWhere((o) => o.clave == clave, orElse: () => OrigenPagoDeuda.fuera);
}

/// Se tira si un pago que sale de una caja no tiene sesión de caja abierta
/// donde grabar el movimiento.
class SinCajaAbiertaException implements Exception {
  const SinCajaAbiertaException();
}

/// Cargos menos pagos, sin anulados.
int _saldoDe(Iterable<MovimientoDeuda> movimientos) => movimientos
    .where((m) => m.anuladoEn == null)
    .fold(0, (a, m) => a + (m.tipo == 'CARGO' ? m.montoCentavos : -m.montoCentavos));

Future<int> saldoDeuda(AppDatabase db, int proveedorId) async {
  final filas = await (db.select(db.movimientosDeuda)..where((m) => m.proveedorId.equals(proveedorId))).get();
  return _saldoDe(filas);
}

/// Saldo de cada proveedor con movimientos (los que nunca tuvieron, no
/// aparecen). Una sola consulta: la lista de Proveedores lo pide entera.
Future<Map<int, int>> saldosDeuda(AppDatabase db) async {
  final filas = await db.select(db.movimientosDeuda).get();
  final porProveedor = <int, List<MovimientoDeuda>>{};
  for (final f in filas) {
    porProveedor.putIfAbsent(f.proveedorId, () => []).add(f);
  }
  return {for (final e in porProveedor.entries) e.key: _saldoDe(e.value)};
}

/// Más nuevos primero (por fecha y, a igual fecha, por orden de carga).
Future<List<MovimientoDeuda>> listarMovimientosDeuda(AppDatabase db, int proveedorId) {
  return (db.select(db.movimientosDeuda)
        ..where((m) => m.proveedorId.equals(proveedorId))
        ..orderBy([(m) => OrderingTerm.desc(m.fecha), (m) => OrderingTerm.desc(m.id)]))
      .get();
}

/// Anota que el dueño le debe [montoCentavos] más a [proveedorId].
Future<int> cargarDeuda(
  AppDatabase db, {
  required int proveedorId,
  required int montoCentavos,
  required DateTime fecha,
  String? nota,
  required int usuarioId,
}) async {
  if (montoCentavos <= 0) throw ArgumentError('El monto de la deuda tiene que ser mayor a 0');
  return db.into(db.movimientosDeuda).insert(
        MovimientosDeudaCompanion.insert(
          proveedorId: proveedorId,
          tipo: 'CARGO',
          montoCentavos: montoCentavos,
          fecha: fecha,
          nota: Value(_limpiar(nota)),
          usuarioId: usuarioId,
        ),
      );
}

/// Paga [montoCentavos] a un proveedor. Si hay deuda cargada, baja la deuda;
/// si el pago es mayor (o no hay deuda), la parte que no estaba cargada se
/// anota sola como un cargo "Pago sin deuda previa" justo antes del pago —
/// así se le puede pagar a un proveedor sin cargarle deuda antes, el gasto
/// queda registrado y el saldo nunca queda negativo.
///
/// Si sale de una caja ([OrigenPagoDeuda.cajon]/[OrigenPagoDeuda.mp]/
/// [OrigenPagoDeuda.lata]) graba en la misma transacción el movimiento de
/// caja PAGO_PROVEEDOR con el proveedor puesto — mismo criterio que
/// `pagarProveedor` y que el gasto rápido: el arqueo baja lo que salió.
Future<int> pagarDeuda(
  AppDatabase db, {
  required int proveedorId,
  required int montoCentavos,
  required OrigenPagoDeuda origen,
  String? nota,
  required int usuarioId,
  int? sesionCajaId,
  DateTime? fecha,
}) async {
  if (montoCentavos <= 0) throw ArgumentError('El monto del pago tiene que ser mayor a 0');
  return db.transaction(() async {
    final saldo = await saldoDeuda(db, proveedorId);
    final hoy = fecha ?? DateTime.now();
    final sinCargar = montoCentavos - saldo;
    if (sinCargar > 0) {
      await db.into(db.movimientosDeuda).insert(
            MovimientosDeudaCompanion.insert(
              proveedorId: proveedorId,
              tipo: 'CARGO',
              montoCentavos: sinCargar,
              fecha: hoy,
              nota: const Value('Pago sin deuda previa'),
              usuarioId: usuarioId,
            ),
          );
    }

    int? movimientoCajaId;
    if (origen != OrigenPagoDeuda.fuera) {
      if (sesionCajaId == null) throw const SinCajaAbiertaException();
      final proveedor = await (db.select(db.proveedores)..where((p) => p.id.equals(proveedorId))).getSingle();
      movimientoCajaId = await _movimientoDeCaja(
        db,
        origen: origen,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        proveedorId: proveedorId,
        montoCentavos: montoCentavos,
        nota: 'Pago a ${proveedor.nombre} — cuenta corriente${_limpiar(nota) == null ? '' : ' (${_limpiar(nota)})'}',
      );
    }

    return db.into(db.movimientosDeuda).insert(
          MovimientosDeudaCompanion.insert(
            proveedorId: proveedorId,
            tipo: 'PAGO',
            montoCentavos: montoCentavos,
            fecha: hoy,
            nota: Value(_limpiar(nota)),
            usuarioId: usuarioId,
            origenPago: Value(origen.clave),
            movimientoCajaId: Value(movimientoCajaId),
          ),
        );
  });
}

/// Anula un cargo o un pago: deja de contar en el saldo. Un pago que salió
/// de una caja se devuelve con un movimiento de caja de signo contrario en la
/// sesión ABIERTA de hoy (el original no se toca ni se borra, Regla 6) — por
/// eso hace falta [sesionCajaId] en ese caso.
///
/// No deja anular un cargo si después de anularlo el saldo quedaría negativo
/// (hay pagos que dependen de él): primero se anulan esos pagos.
Future<void> anularMovimientoDeuda(
  AppDatabase db, {
  required int movimientoId,
  required int usuarioId,
  int? sesionCajaId,
}) {
  return db.transaction(() async {
    final mov = await (db.select(db.movimientosDeuda)..where((m) => m.id.equals(movimientoId))).getSingle();
    if (mov.anuladoEn != null) throw ArgumentError('Este movimiento ya está anulado');

    if (mov.tipo == 'CARGO') {
      final saldo = await saldoDeuda(db, mov.proveedorId);
      if (saldo - mov.montoCentavos < 0) {
        throw ArgumentError('Hay pagos que dependen de este cargo: anulá primero esos pagos');
      }
    } else if (mov.movimientoCajaId != null) {
      if (sesionCajaId == null) throw const SinCajaAbiertaException();
      final original = await (db.select(db.movimientosDeCaja)..where((m) => m.id.equals(mov.movimientoCajaId!))).getSingle();
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionCajaId,
              cajaId: original.cajaId,
              usuarioId: usuarioId,
              tipo: 'PAGO_PROVEEDOR',
              montoCentavos: -original.montoCentavos,
              proveedorId: Value(mov.proveedorId),
              medioPagoId: Value(original.medioPagoId),
              nota: const Value('Anulación de pago — cuenta corriente'),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );
    }

    await (db.update(db.movimientosDeuda)..where((m) => m.id.equals(movimientoId))).write(
      MovimientosDeudaCompanion(anuladoEn: Value(DateTime.now())),
    );
  });
}

Future<int> _movimientoDeCaja(
  AppDatabase db, {
  required OrigenPagoDeuda origen,
  required int sesionCajaId,
  required int usuarioId,
  required int proveedorId,
  required int montoCentavos,
  required String nota,
}) async {
  final deLata = origen == OrigenPagoDeuda.lata;
  final caja = await (db.select(db.cajas)..where((c) => c.esLata.equals(deLata))).getSingle();
  // Mercado Pago no es una fila de `Cajas`: mismo criterio que `pagarProveedor`
  // — cajón normal + `medioPagoId` de MP, y es ese id el que separa uno de
  // otro para `gastosEnEfectivoDelDia`/`gastosPorMpDelDia`.
  final medioPagoId = origen == OrigenPagoDeuda.mp
      ? (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id
      : null;
  return db.into(db.movimientosDeCaja).insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionCajaId,
          cajaId: caja.id,
          usuarioId: usuarioId,
          tipo: 'PAGO_PROVEEDOR',
          montoCentavos: montoCentavos,
          proveedorId: Value(proveedorId),
          medioPagoId: Value(medioPagoId),
          nota: Value(nota),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

String? _limpiar(String? texto) {
  final t = texto?.trim();
  return t == null || t.isEmpty ? null : t;
}
