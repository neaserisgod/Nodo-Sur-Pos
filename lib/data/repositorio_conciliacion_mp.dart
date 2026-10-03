// Lo que la app registró como cobrado por Mercado Pago en un turno, y la
// conciliación contra lo que informa Mercado Pago (`domain/conciliacion_mp.dart`).
// La lectura de Mercado Pago llega como función: la base no sabe de red.

import 'package:drift/drift.dart';

import '../domain/conciliacion_mp.dart';
import 'database.dart';

/// Pagos no en efectivo de las ventas no anuladas de [sesionId].
Future<List<PagoMpRegistrado>> pagosMpRegistrados(AppDatabase db, int sesionId) async {
  final filas = await (db.select(db.pagos).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.pagos.ventaId)),
    innerJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(db.pagos.medioPagoId)),
  ])..where(db.ventas.sesionCajaId.equals(sesionId) & db.ventas.anuladaEn.isNull() & db.mediosDePago.esEfectivo.equals(false)))
      .get();
  return [
    for (final f in filas)
      PagoMpRegistrado(
        ventaId: f.readTable(db.ventas).id,
        fecha: f.readTable(db.ventas).fecha,
        montoCentavos: f.readTable(db.pagos).montoCentavos,
        canal: f.readTable(db.pagos).canal,
      ),
  ];
}

typedef LeerCobrosMp = Future<({List<CobroMp> cobros, bool truncado})> Function(DateTime desde, DateTime hasta);

/// Concilia el turno [sesionId]: de la apertura al cierre (o a ahora, si sigue abierto).
Future<ConciliacionMp> conciliarMpDeSesion(AppDatabase db, int sesionId, LeerCobrosMp leer, {DateTime? ahora}) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final hasta = sesion.fechaCierre ?? ahora ?? DateTime.now();
  final leidos = await leer(sesion.fechaApertura, hasta);
  return conciliarMp(cobros: leidos.cobros, registrados: await pagosMpRegistrados(db, sesionId), truncado: leidos.truncado);
}
