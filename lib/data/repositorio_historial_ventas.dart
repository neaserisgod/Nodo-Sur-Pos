// Historial de ventas: listado filtrable de ventas individuales, para la
// pestaña nueva de "Reportes" (escritorio) y la pantalla del celular
// (El dueño, 2026-09-07: "hagamos la sección de reportes... con el historial
// de ventas, lo mismo para desktop, que sea filtrable... tipo mercado
// pago... que también sirva para un control manual en caso de desconfiar
// de los números"). Mismo criterio de agrupar pagos en "efectivo/virtual/
// mixto" que ya usa `ventasDeDiaHistorico` (Regla 3), acá con el canal
// (QR/Débito) aparte para poder filtrar por esos dos por separado.

import 'package:drift/drift.dart';

import 'numero_venta.dart';
import 'database.dart';

/// 'efectivo' | 'qr' | 'debitCard' | 'mixto' — más granular que el
/// `medioResumen` de la carga histórica porque acá interesa poder filtrar
/// QR y Débito por separado (El dueño: "tipo mercado pago").
enum MedioVentaHistorial { efectivo, qr, debitCard, mixto, creditCard }

class VentaDelHistorial {
  final int ventaId;

  /// Número de venta global (`ventas.numero`); null en las ventas anteriores a la v48.
  final String? numero;
  final DateTime fecha;
  final int totalCentavos;
  final MedioVentaHistorial medio;
  final String detalle;

  /// true si `anuladaEn` no es null (`anularVenta`,
  /// `repositorio_edicion_venta.dart`) — la venta se sigue mostrando, solo
  /// que marcada (Regla 6, nunca se pierde el rastro).
  final bool anulada;

  /// Si la sesión de caja de esta venta sigue 'ABIERTA' — condición para
  /// poder anularla (El dueño, 2026-09-13: anular una venta de un cierre ya
  /// arqueado descuadraría ese arqueo). Se calcula acá, no en la UI, para
  /// que el celular no necesite una segunda consulta solo para esto.
  final bool sesionAbierta;

  /// Cómo se nombra en pantalla: el número global o, en las viejas, el id local.
  String get etiqueta => etiquetaDeVenta(id: ventaId, numero: numero);

  const VentaDelHistorial({
    required this.ventaId,
    this.numero,
    required this.fecha,
    required this.totalCentavos,
    required this.medio,
    required this.detalle,
    required this.anulada,
    required this.sesionAbierta,
  });
}

/// Ventas entre [desde] (inclusive) y [hasta] (exclusive), de más nueva a
/// más vieja. [filtroMedio] null = todas.
Future<List<VentaDelHistorial>> historialDeVentas(
  AppDatabase db, {
  required DateTime desde,
  required DateTime hasta,
  MedioVentaHistorial? filtroMedio,
}) async {
  final mediosDePago = await db.select(db.mediosDePago).get();
  bool esEfectivo(int medioPagoId) =>
      mediosDePago.firstWhere((m) => m.id == medioPagoId).esEfectivo;

  final sesionesAbiertas = <int>{
    for (final s in await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.estado.equals('ABIERTA'))).get())
      s.id,
  };

  final ventas = await (db.select(db.ventas)
        ..where((v) => v.fecha.isBiggerOrEqualValue(desde) & v.fecha.isSmallerThanValue(hasta))
        ..orderBy([(v) => OrderingTerm.desc(v.fecha)]))
      .get();

  final resultado = <VentaDelHistorial>[];
  for (final v in ventas) {
    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(v.id))).get();

    final MedioVentaHistorial medio;
    if (pagos.length > 1) {
      medio = MedioVentaHistorial.mixto;
    } else if (pagos.isEmpty || esEfectivo(pagos.single.medioPagoId)) {
      medio = MedioVentaHistorial.efectivo;
    } else {
      medio = switch (pagos.single.canal) {
        'debit_card' => MedioVentaHistorial.debitCard,
        'credit_card' => MedioVentaHistorial.creditCard,
        _ => MedioVentaHistorial.qr,
      };
    }

    if (filtroMedio != null && medio != filtroMedio) continue;

    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(v.id))).get();
    final detalle = lineas
        .map((l) => l.esPesable ? '${l.nombreProductoFoto} (${l.gramos}g)' : '${l.nombreProductoFoto} x${l.cantidad}')
        .join(', ');

    resultado.add(
      VentaDelHistorial(
        ventaId: v.id,
        numero: v.numero,
        fecha: v.fecha,
        totalCentavos: v.totalCentavos,
        medio: medio,
        detalle: detalle,
        anulada: v.anuladaEn != null,
        sesionAbierta: sesionesAbiertas.contains(v.sesionCajaId),
      ),
    );
  }
  return resultado;
}
