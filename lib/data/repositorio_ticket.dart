// Conecta una venta ya persistida con el `Ticket` de dominio (fase 1,
// lib/domain/ticket.dart) — el conector que había quedado pendiente desde
// la fase 1 ("todavía no existe el código que convierte...") — y la
// configuración de impresión de la fase 10.

import 'package:drift/drift.dart';

import '../domain/pesables.dart';
import '../domain/ticket.dart';
import 'database.dart';

Future<Ticket> ticketDeVenta(AppDatabase db, int ventaId) async {
  final venta = await (db.select(
    db.ventas,
  )..where((v) => v.id.equals(ventaId))).getSingle();
  final lineas = await (db.select(
    db.lineasDeVenta,
  )..where((l) => l.ventaId.equals(ventaId))).get();
  final usuario = await (db.select(
    db.usuarios,
  )..where((u) => u.id.equals(venta.usuarioId))).getSingle();

  final lineasTicket = lineas.map((linea) {
    final subtotal = linea.esPesable
        ? subtotalPesable(
            montoPorKiloCentavos: linea.precioUnitarioCentavos,
            gramos: linea.gramos!,
          )
        : linea.precioUnitarioCentavos * (linea.cantidad ?? 1);

    return LineaTicket(
      nombreProducto: linea.nombreProductoFoto,
      cantidad: linea.esPesable ? 1 : (linea.cantidad ?? 1),
      gramos: linea.esPesable ? linea.gramos : null,
      subtotalCentavos: subtotal,
    );
  }).toList();

  return construirTicket(
    numero: venta.numero ?? '#${venta.id}',
    fecha: venta.fecha,
    vendedor: usuario.nombre,
    lineas: lineasTicket,
    desglose: DesgloseTicket(
      recargoCigarrillosCentavos: venta.recargoCigarrillosCentavos,
      descuentoCentavos: venta.descuentoCentavos,
      redondeoCentavos: venta.redondeoCentavos,
    ),
  );
}

// ─── Configuración de impresión (fase 10) ───────────────────────────────

Future<void> configurarMpAccessToken(AppDatabase db, String? valor) {
  return db
      .update(db.configuracionTabla)
      .write(ConfiguracionTablaCompanion(mpAccessToken: Value(valor)));
}

Future<void> configurarMpTerminalId(AppDatabase db, String? valor) {
  return db
      .update(db.configuracionTabla)
      .write(ConfiguracionTablaCompanion(mpTerminalId: Value(valor)));
}

/// Fase 12: la terminal que cobra por QR/Débito — campo separado de
/// [configurarMpTerminalId] aunque hoy señalen el mismo posnet físico.
Future<void> configurarMpTerminalCobroId(AppDatabase db, String? valor) {
  return db
      .update(db.configuracionTabla)
      .write(ConfiguracionTablaCompanion(mpTerminalCobroId: Value(valor)));
}

Future<void> configurarCarpetaTickets(AppDatabase db, String? valor) {
  return db
      .update(db.configuracionTabla)
      .write(ConfiguracionTablaCompanion(rutaTicketsCarpeta: Value(valor)));
}

/// Búsqueda mínima para reimprimir (fase 10, adelantada de la fase 9): por
/// número de venta exacto, o por día si no se da un número. Sin ambos
/// filtros, trae las últimas ventas nomás — para no dejar la pantalla vacía
/// la primera vez que se abre.
Future<List<FilaVenta>> buscarVentasParaReimprimir(
  AppDatabase db, {
  DateTime? fecha,
  int? numero,
}) {
  final query = db.select(db.ventas);
  if (numero != null) {
    query.where((v) => v.id.equals(numero));
  } else if (fecha != null) {
    final inicio = DateTime(fecha.year, fecha.month, fecha.day);
    final fin = inicio.add(const Duration(days: 1));
    query.where(
      (v) =>
          v.fecha.isBiggerOrEqualValue(inicio) &
          v.fecha.isSmallerThanValue(fin),
    );
  }
  query
    ..orderBy([(v) => OrderingTerm.desc(v.fecha)])
    ..limit(30);
  return query.get();
}
