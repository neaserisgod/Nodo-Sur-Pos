// Fiados y encargues (Regla 15), sobre la misma tabla `pendientes` de la
// fase 2: comparten forma, esta es la fase que finalmente les da uso.
//
// Cobrar un fiado genera una venta real por el monto exacto adeudado —no se
// le aplica recargo de cigarrillos (nunca los tiene) ni la fórmula de
// redondeo de venta (Regla 15 no la menciona, y redondear cambiaría el monto
// respecto a lo anotado, que es justo lo que no debería pasar al saldar una
// deuda ya fija)— marcada `esFiado` para que quede trazable en el historial.
// Un encargue resuelto no genera venta: es "ya te traje lo que pediste", no
// necesariamente un cobro.

import 'package:drift/drift.dart';

import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_ventas.dart';

Future<List<Pendiente>> listarFiados(AppDatabase db) {
  return (db.select(db.pendientes)
        ..where((p) => p.tipo.equals('FIADO') & p.estado.equals('PENDIENTE'))
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion)]))
      .get();
}

Future<int> totalFiadosPendientesCentavos(AppDatabase db) async {
  final query = db.selectOnly(db.pendientes)
    ..addColumns([db.pendientes.montoCentavos.sum()])
    ..where(db.pendientes.tipo.equals('FIADO') & db.pendientes.estado.equals('PENDIENTE'));
  final fila = await query.getSingle();
  return fila.read(db.pendientes.montoCentavos.sum()) ?? 0;
}

Future<int> crearFiado(
  AppDatabase db, {
  String? nombreLibre,
  int? clienteId,
  required int montoCentavos,
  required int usuarioId,
}) {
  return db.into(db.pendientes).insert(
        PendientesCompanion.insert(
          tipo: 'FIADO',
          clienteId: Value(clienteId),
          nombreLibre: Value(nombreLibre),
          montoCentavos: Value(montoCentavos),
          usuarioId: usuarioId,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

/// Cobra el fiado [pendienteId]: registra una venta de una sola línea
/// "Varios" por el monto exacto adeudado y tilda el pendiente como resuelto.
Future<int> cobrarFiado(
  AppDatabase db, {
  required int pendienteId,
  required int sesionCajaId,
  required int usuarioId,
  required int medioPagoId,
  required bool medioEsEfectivo,
}) async {
  final pendiente =
      await (db.select(db.pendientes)..where((p) => p.id.equals(pendienteId))).getSingle();
  final monto = pendiente.montoCentavos!;
  // Se registra bajo el producto "Varios" del catálogo (Regla 5/9): no tiene
  // costo ni descuenta stock, que es exactamente lo que corresponde acá.
  final varios = await (db.select(db.productos)..where((p) => p.esVarios.equals(true))).getSingle();

  final venta = Venta(lineas: [
    LineaVentaPorUnidad(
      productoId: varios.id.toString(),
      nombreProducto: 'Fiado cobrado${pendiente.nombreLibre != null ? ' (${pendiente.nombreLibre})' : ''}',
      proveedorId: null,
      cantidad: 1,
      esVarios: true,
      precioUnitarioCentavos: monto,
      costoUnitarioCentavos: null,
    ),
  ]);

  final (ventaId, _) = await registrarVenta(
    db,
    venta: venta,
    resultado: ResultadoTotalVenta(
      subtotalCentavos: monto,
      recargoCigarrillosCentavos: 0,
      redondeoCentavos: 0,
      totalCentavos: monto,
    ),
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    pagos: [
      PagoARegistrar(medioPagoId: medioPagoId, montoCentavos: monto, esEfectivo: medioEsEfectivo),
    ],
    esFiado: true,
  );

  await (db.update(db.pendientes)..where((p) => p.id.equals(pendienteId))).write(
    PendientesCompanion(
      estado: const Value('RESUELTO'),
      ventaId: Value(ventaId),
      fechaResuelta: Value(DateTime.now()),
      actualizadoEn: Value(DateTime.now()),
    ),
  );

  return ventaId;
}

Future<List<Pendiente>> listarEncargues(AppDatabase db) {
  return (db.select(db.pendientes)
        ..where((p) => p.tipo.equals('ENCARGUE') & p.estado.equals('PENDIENTE'))
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion)]))
      .get();
}

Future<int> crearEncargue(
  AppDatabase db, {
  String? nombreLibre,
  int? clienteId,
  required String descripcion,
  required int usuarioId,
}) {
  return db.into(db.pendientes).insert(
        PendientesCompanion.insert(
          tipo: 'ENCARGUE',
          clienteId: Value(clienteId),
          nombreLibre: Value(nombreLibre),
          descripcion: Value(descripcion),
          usuarioId: usuarioId,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> resolverEncargue(AppDatabase db, int id) {
  return (db.update(db.pendientes)..where((p) => p.id.equals(id))).write(
    PendientesCompanion(
      estado: const Value('RESUELTO'),
      fechaResuelta: Value(DateTime.now()),
      actualizadoEn: Value(DateTime.now()),
    ),
  );
}

/// Cobra una deuda en efectivo o Mercado Pago (el medio se busca acá para que PC, celular y servidor no lo repitan).
Future<int> cobrarDeuda(
  AppDatabase db, {
  required int pendienteId,
  required int sesionCajaId,
  required int usuarioId,
  required bool efectivo,
}) async {
  final medio = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(efectivo))).getSingle();
  return cobrarFiado(
    db,
    pendienteId: pendienteId,
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    medioPagoId: medio.id,
    medioEsEfectivo: efectivo,
  );
}
