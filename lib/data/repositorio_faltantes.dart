// Anota a dónde fue un faltante del cierre (`domain/faltantes_cierre.dart`). Cada destino reusa el registro que ya
// existe para esa salida, así el faltante explicado cuenta igual que si se hubiera anotado en el momento: el pago a un
// proveedor baja su deuda, el de un fijo lo marca pagado en Equilibrio, y un gasto personal es un RETIRO (lo que
// Equilibrio resta como "ya retirado", El dueño 2026-10-07: "mis gastos salieron de la cuenta del negocio").

import 'package:drift/drift.dart';

import '../domain/faltantes_cierre.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_deuda_proveedores.dart' show OrigenPagoDeuda, pagarDeuda;
import 'repositorio_equilibrio.dart' show registrarPagoFijo;
import 'repositorio_gastos.dart' show MedioGasto, registrarGastoRapido;
import 'repositorio_ventas.dart' show verificarSesionAbierta;

enum DestinoFaltante { gastoMio, proveedor, fijo, negocio }

/// Un fijo siempre se paga del cajón o de Mercado Pago (`registrarPagoFijo` no tiene lata): desde la lata no se ofrece.
bool destinoPosible(DestinoFaltante destino, CajaDelCierre caja) => destino != DestinoFaltante.fijo || caja != CajaDelCierre.lata;

Future<void> anotarFaltante(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required CajaDelCierre caja,
  required int montoCentavos,
  required DestinoFaltante destino,
  int? proveedorId,
  int? gastoFijoId,
  String? nota,
}) async {
  if (montoCentavos <= 0) throw ArgumentError('El monto tiene que ser mayor a 0');
  if (!destinoPosible(destino, caja)) throw ArgumentError('Un fijo no se paga desde la lata');
  final detalle = nota?.trim().isEmpty ?? true ? null : nota!.trim();
  switch (destino) {
    case DestinoFaltante.gastoMio:
      await _retiro(db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, caja: caja, montoCentavos: montoCentavos, nota: detalle);
    case DestinoFaltante.negocio:
      await registrarGastoRapido(
        db,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        montoCentavos: montoCentavos,
        medio: _medio(caja),
        motivo: detalle ?? 'Faltante del cierre',
      );
    case DestinoFaltante.proveedor:
      if (proveedorId == null) throw ArgumentError('Falta elegir el proveedor');
      await pagarDeuda(
        db,
        proveedorId: proveedorId,
        montoCentavos: montoCentavos,
        origen: switch (caja) {
          CajaDelCierre.efectivo => OrigenPagoDeuda.cajon,
          CajaDelCierre.mercadoPago => OrigenPagoDeuda.mp,
          CajaDelCierre.lata => OrigenPagoDeuda.lata,
        },
        nota: detalle,
        usuarioId: usuarioId,
        sesionCajaId: sesionCajaId,
      );
    case DestinoFaltante.fijo:
      if (gastoFijoId == null) throw ArgumentError('Falta elegir el fijo');
      await registrarPagoFijo(
        db,
        gastoFijoId: gastoFijoId,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        montoCentavos: montoCentavos,
        pagadoConMp: caja == CajaDelCierre.mercadoPago,
      );
  }
}

MedioGasto _medio(CajaDelCierre caja) => switch (caja) {
  CajaDelCierre.efectivo => MedioGasto.cajonNormal,
  CajaDelCierre.mercadoPago => MedioGasto.mercadoPago,
  CajaDelCierre.lata => MedioGasto.lata,
};

/// Mismo armado de caja y medio que el gasto rápido (MP va en la caja normal con `medioPagoId` de MP), con tipo RETIRO.
Future<void> _retiro(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required CajaDelCierre caja,
  required int montoCentavos,
  String? nota,
}) => db.transaction(() async {
  await verificarSesionAbierta(db, sesionCajaId);
  final cajaFila = await (db.select(db.cajas)..where((c) => c.esLata.equals(caja == CajaDelCierre.lata))).getSingle();
  final medioPagoId = caja == CajaDelCierre.mercadoPago
      ? (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id
      : null;
  await db.into(db.movimientosDeCaja).insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionCajaId,
          cajaId: cajaFila.id,
          usuarioId: usuarioId,
          tipo: 'RETIRO',
          montoCentavos: montoCentavos,
          medioPagoId: Value(medioPagoId),
          nota: Value(nota == null ? 'Gasto personal' : 'Gasto personal: $nota'),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
});
