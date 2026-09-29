// Ingreso rápido (Alt++ en Venta, Bruno 2026-09-13: "un botón de ingreso de
// dinero, evidentemente siguiendo con las cajas que hay") — espejo de
// "Gasto rápido" (`repositorio_gastos.dart`): mismas tres cajas
// (`MedioGasto`, reusado tal cual — las cajas para meter plata son las
// mismas que para sacarla, no hace falta un enum aparte), pero suma en vez
// de restar. `movimientos_de_caja.tipo` es una columna de texto libre, sin
// constraint — agregar 'INGRESO' como valor nuevo no pidió ninguna
// migración de esquema.

import 'package:drift/drift.dart';

import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_gastos.dart' show MedioGasto;
import 'repositorio_ventas.dart' show verificarSesionAbierta;

/// Anota un ingreso rápido y devuelve el id del movimiento de caja creado.
/// Mismo criterio que `registrarGastoRapido` para Mercado Pago: no es una
/// fila de `Cajas`, así que `cajaId` queda en la caja normal y lo que
/// distingue el ingreso es `medioPagoId`.
Future<int> registrarIngresoRapido(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  required MedioGasto medio,
  String? motivo,
}) {
  // Mismo motivo que `registrarGastoRapido` (Bruno, 2026-09-19: "aislar los
  // usuarios para que no se pisen") — verificar y escribir en la misma
  // transacción.
  return db.transaction(() async {
    await verificarSesionAbierta(db, sesionCajaId);

    final caja = await (db.select(
      db.cajas,
    )..where((c) => c.esLata.equals(medio == MedioGasto.lata))).getSingle();
    final medioPagoId = medio == MedioGasto.mercadoPago
        ? (await (db.select(
                db.mediosDePago,
              )..where((m) => m.esEfectivo.equals(false)))
              .getSingle())
            .id
        : null;

    return db
        .into(db.movimientosDeCaja)
        .insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionCajaId,
            cajaId: caja.id,
            usuarioId: usuarioId,
            tipo: 'INGRESO',
            montoCentavos: montoCentavos,
            medioPagoId: Value(medioPagoId),
            nota: Value(motivo?.trim().isEmpty ?? true ? null : motivo!.trim()),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  });
}
