// Avisos de Mercado Pago de este equipo (etapa D, 2026-10-04): guardarlos, llevar el cursor y decidir cuáles mostrar en la
// campanita cruzándolos con las ventas y órdenes de la base (`domain/avisos_mp.dart`). No toca la caja ni el stock.

import 'package:drift/drift.dart';

import '../domain/avisos_mp.dart';
import 'database.dart';

/// Cuánto se guarda: lo mismo que en el sitio, y alcanza para cruzar un contracargo con la venta (que llega semanas después).
const vidaAvisosMp = Duration(days: 30);
const _ventanaDeVentas = Duration(days: 35);

AvisoMp _aAviso(AvisoMpFila f) => AvisoMp(
  idServidor: f.idServidor,
  tipo: TipoAvisoMp.values.firstWhere((t) => t.name == f.tipo, orElse: () => TipoAvisoMp.cobro),
  mpId: f.mpId,
  pagoId: f.pagoId,
  montoCentavos: f.montoCentavos,
  referencia: f.referencia,
  estado: f.estado,
  detalle: f.detalle,
  fecha: f.fecha,
  creado: f.creado,
  visto: f.visto,
);

/// Guarda los avisos nuevos (uno que ya estaba, por el id del sitio, se ignora) y devuelve cuántos eran nuevos.
Future<int> guardarAvisosMp(AppDatabase db, List<AvisoMp> avisos) async {
  var nuevos = 0;
  for (final a in avisos) {
    // `insertOrIgnore` devuelve el último rowid aunque no haya insertado, así que no sirve para contar: se mira antes.
    final yaEsta = await (db.select(db.avisosMp)..where((f) => f.idServidor.equals(a.idServidor))).getSingleOrNull() != null;
    if (yaEsta) continue;
    await db.into(db.avisosMp).insert(
      AvisosMpCompanion.insert(
        idServidor: a.idServidor,
        tipo: a.tipo.name,
        mpId: a.mpId,
        pagoId: Value(a.pagoId),
        montoCentavos: Value(a.montoCentavos),
        referencia: Value(a.referencia),
        estado: Value(a.estado),
        detalle: Value(a.detalle),
        fecha: Value(a.fecha),
        creado: a.creado,
      ),
    );
    nuevos++;
  }
  return nuevos;
}

/// El último aviso que este equipo ya tiene: con esto se le piden al sitio solo los que faltan.
Future<int> ultimoIdAvisoMp(AppDatabase db) async {
  final fila = await (db.select(db.avisosMp)..orderBy([(a) => OrderingTerm.desc(a.idServidor)])..limit(1)).getSingleOrNull();
  return fila?.idServidor ?? 0;
}

/// "Visto": desaparece este aviso y los anteriores del mismo contracargo o reclamo. Si Mercado Pago manda uno nuevo, vuelve.
Future<void> marcarAvisoMpVisto(AppDatabase db, AvisoMp aviso) async {
  await (db.update(db.avisosMp)..where((a) => a.tipo.equals(aviso.tipo.name) & a.mpId.equals(aviso.mpId) & a.idServidor.isSmallerOrEqualValue(aviso.idServidor)))
      .write(const AvisosMpCompanion(visto: Value(true)));
}

Future<void> limpiarAvisosMpViejos(AppDatabase db, {DateTime? ahora}) async {
  final corte = (ahora ?? DateTime.now()).subtract(vidaAvisosMp);
  await (db.delete(db.avisosMp)..where((a) => a.creado.isSmallerThanValue(corte))).go();
}

/// Lo que va en la campanita ahora mismo. Se calcula de nuevo cada vez: un cobro que esperaba su venta puede haberla recibido.
Future<List<AvisoParaMostrar>> avisosMpParaMostrar(AppDatabase db, {DateTime? ahora}) async {
  final ya = ahora ?? DateTime.now();
  final filas = await db.select(db.avisosMp).get();
  if (filas.isEmpty) return const [];

  final desde = ya.subtract(_ventanaDeVentas);
  final ordenes = await (db.select(db.ordenesCobroPendientes)..where((o) => o.creadaEn.isBiggerOrEqualValue(desde))).get();
  final pagos = await (db.select(db.pagos).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.pagos.ventaId)),
    innerJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(db.pagos.medioPagoId)),
  ])..where(db.ventas.anuladaEn.isNull() & db.mediosDePago.esEfectivo.equals(false) & db.ventas.fecha.isBiggerOrEqualValue(desde)))
      .get();

  return avisosParaMostrar(
    avisos: filas.map(_aAviso).toList(),
    ordenes: [for (final o in ordenes) OrdenConocida(referencia: o.externalReference, ventaId: o.ventaId)],
    ventas: [
      for (final f in pagos)
        VentaMp(
          ventaId: f.readTable(db.ventas).id,
          numero: f.readTable(db.ventas).numero,
          fecha: f.readTable(db.ventas).fecha,
          montoCentavos: f.readTable(db.pagos).montoCentavos,
        ),
    ],
    ahora: ya,
  );
}
