// Gasto rápido (Alt+guion en Venta, `CLAUDE.md`): la forma más rápida de
// anotar un gasto sin salir de la pantalla de venta. Un gasto nunca es una
// venta (Regla 11): escribe directo en `movimientos_de_caja`, no toca
// `ventas`.
//
// Extraído del diálogo de gasto rápido (hoy `lib/ui/venta/dialogo_movimiento_rapido.dart`) (2026-09-07, spike
// companion app): esa lógica vivía inline en el diálogo — la companion app
// necesita el mismo movimiento sin pasar por ningún widget, así que quedó
// acá para que las dos formas de cargarlo (el diálogo de la venta, la API
// de la companion) usen la misma función (Regla 3: una sola fórmula, un
// solo lugar).

import 'package:drift/drift.dart';

import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_ventas.dart' show verificarSesionAbierta;

enum MedioGasto { cajonNormal, lata, mercadoPago }

/// Anota un gasto rápido y devuelve el id del movimiento de caja creado.
///
/// Con [proveedorId] es un pago a ese proveedor hecho en el momento (sin
/// deuda cargada antes): queda como 'PAGO_PROVEEDOR' con el proveedor puesto,
/// que para el arqueo es lo mismo que un gasto (`tiposEgresoDeCaja`) y en el
/// historial de movimientos se ve a quién se le pagó.
///
/// Un gasto pagado con Mercado Pago no sale de ningún cajón físico, pero
/// `cajaId` no es nullable y MP no es una fila de `Cajas` (`DECISIONES.md`)
/// — queda con `cajaId` = caja normal igual que uno en efectivo, y lo que
/// lo distingue de verdad es `medioPagoId`. `gastosEnEfectivoDelDia`/
/// `gastosPorMpDelDia` (`repositorio_cierre.dart`) filtran por ese campo,
/// no solo por caja, para no restarlo dos veces.
Future<int> registrarGastoRapido(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  required MedioGasto medio,
  String? motivo,
  int? proveedorId,
}) {
  // Envuelto junto con `verificarSesionAbierta` en la misma transacción
  // (El dueño, 2026-09-19: "aislar los usuarios para que no se pisen") — sin
  // esto, un gasto rápido mandado justo cuando la caja se cierra en otro
  // dispositivo se grababa igual, contra una sesión ya `CERRADA`, sin que
  // nadie se entere.
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
            tipo: proveedorId == null ? 'GASTO' : 'PAGO_PROVEEDOR',
            montoCentavos: montoCentavos,
            proveedorId: Value(proveedorId),
            medioPagoId: Value(medioPagoId),
            nota: Value(motivo?.trim().isEmpty ?? true ? null : motivo!.trim()),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  });
}
