// Persistencia de una orden de cobro por terminal Point (Fase 12) — el
// puente entre el cliente HTTP (`cobro_posnet.dart`) y la tabla
// `ordenes_cobro_pendientes`. La regla que gobierna todo este archivo:
// [crearOrdenPendiente] se llama SIEMPRE antes del POST a Mercado Pago,
// nunca después — así, si la respuesta del POST se pierde (se cortó la
// conexión, la app se cerró), la clave de idempotencia ya quedó en disco y
// se puede reintentar el mismo POST sin arriesgar un doble cobro.

import 'package:drift/drift.dart';

import '../domain/cobro_posnet.dart' show vencimientoOrdenCobroPosnet;
import 'cobro_posnet.dart' show CobroPosnetException, PasarelaPoint;
import 'database.dart';
import 'identidad_sync.dart';

/// Siembra la orden en disco ANTES de llamar a la API. Devuelve el id de
/// la fila (para las siguientes actualizaciones) junto con la clave de
/// idempotencia y la referencia externa recién generadas, que el llamador
/// manda en el POST.
///
/// Si hay un intento anterior del MISMO cobro (misma sesión, canal y monto) que nunca obtuvo respuesta de Mercado Pago
/// (`ordenIdMp` nulo, sigue 'pendiente') y es más nuevo que lo que vive una orden, se devuelve ese: misma clave de
/// idempotencia, misma referencia. Así el reintento después de un corte de red le pide a Mercado Pago LA MISMA orden en vez de
/// crear una segunda (el cliente podía terminar pagando dos veces, o pagando una orden que la caja ya no seguía). Un rechazo
/// definitivo de Mercado Pago se marca 'rechazada' (`marcarOrdenResuelta`) y por eso nunca se reutiliza; pasado el
/// vencimiento Mercado Pago ya venció esa orden sola y se empieza de nuevo.
Future<({int id, String externalReference, String idempotencyKey})> crearOrdenPendiente(
  AppDatabase db, {
  required int sesionCajaId,
  required String canal,
  required int montoCentavos,
}) {
  return db.transaction(() async {
    final desde = DateTime.now().subtract(vencimientoOrdenCobroPosnet);
    final previa = await (db.select(db.ordenesCobroPendientes)
          ..where(
            (o) =>
                o.sesionCajaId.equals(sesionCajaId) &
                o.canal.equals(canal) &
                o.montoCentavos.equals(montoCentavos) &
                o.estado.equals('pendiente') &
                o.ordenIdMp.isNull() &
                o.ventaId.isNull() &
                o.creadaEn.isBiggerOrEqualValue(desde),
          )
          ..orderBy([(o) => OrderingTerm.desc(o.id)])
          ..limit(1))
        .getSingleOrNull();
    if (previa != null) return (id: previa.id, externalReference: previa.externalReference, idempotencyKey: previa.idempotencyKey);

    // `generarGlobalId()` es el mismo generador de claves random que ya usaba
    // este archivo antes de existir como función compartida (Regla 3) — ver
    // `lib/data/identidad_sync.dart`.
    final externalReference = generarGlobalId();
    final idempotencyKey = generarGlobalId();
    final id = await db.into(db.ordenesCobroPendientes).insert(
          OrdenesCobroPendientesCompanion.insert(
            externalReference: externalReference,
            idempotencyKey: idempotencyKey,
            canal: canal,
            montoCentavos: montoCentavos,
            sesionCajaId: sesionCajaId,
          ),
        );
    return (id: id, externalReference: externalReference, idempotencyKey: idempotencyKey);
  });
}

/// Crea la orden de cobro de punta a punta: la siembra en disco, se la pide a Mercado Pago y guarda el id que responde. Lo
/// comparten la PC, el servidor para el celular y el celular sin PC (Regla 3: una sola secuencia).
///
/// Si Mercado Pago RECHAZA el pedido (4xx) la fila se cierra como 'rechazada': no hay orden ni nada que revisar en el cierre, y
/// un reintento arranca limpio. Si NO se sabe qué pasó ([CobroPosnetException.incierto]: corte de red, plazo vencido, 5xx) la
/// fila queda 'pendiente' y el próximo intento del mismo cobro la reutiliza ([crearOrdenPendiente]) con la misma clave de
/// idempotencia, así nunca hay dos órdenes vivas por el mismo cobro. En los dos casos la excepción sigue de largo para que la
/// pantalla muestre el motivo.
Future<({int ordenPendienteId, String ordenIdMp})> iniciarOrdenDeCobro(
  AppDatabase db,
  PasarelaPoint pasarela, {
  required int sesionCajaId,
  required String canal,
  required int montoCentavos,
}) async {
  final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionCajaId, canal: canal, montoCentavos: montoCentavos);
  try {
    final creada = await pasarela.crear(
      externalReference: pendiente.externalReference,
      idempotencyKey: pendiente.idempotencyKey,
      montoCentavos: montoCentavos,
      canal: canal,
    );
    await marcarOrdenConId(db, id: pendiente.id, ordenIdMp: creada.ordenIdMp);
    return (ordenPendienteId: pendiente.id, ordenIdMp: creada.ordenIdMp);
  } on CobroPosnetException catch (e) {
    if (!e.incierto) await marcarOrdenResuelta(db, id: pendiente.id, estado: 'rechazada');
    rethrow;
  }
}

/// Se llama apenas el POST responde con éxito — recién ahí existe un id de
/// Mercado Pago contra el cual consultar. No toca `estado`: el status
/// crudo que devuelve el POST ("created") es de Mercado Pago, no del
/// vocabulario propio de esta tabla (pendiente/aprobada/rechazada/
/// cancelada) — la orden sigue "pendiente" hasta que el polling la
/// resuelva, tenga o no ya un id asignado.
Future<void> marcarOrdenConId(
  AppDatabase db, {
  required int id,
  required String ordenIdMp,
}) {
  return (db.update(db.ordenesCobroPendientes)..where((o) => o.id.equals(id))).write(
    OrdenesCobroPendientesCompanion(ordenIdMp: Value(ordenIdMp)),
  );
}

/// Cierra el ciclo de esta orden: aprobada (con la venta que generó),
/// rechazada, o cancelada por el dueño desde el diálogo. Un timeout o un corte
/// de conexión a mitad del polling NO llama a esto — la fila queda en
/// 'pendiente' a propósito, para que [ordenesSinResolverDeSesion] la
/// encuentre después (Regla de Fase 12: un resultado "no sé si se cobró"
/// nunca se asume, queda visible en el Cierre).
Future<void> marcarOrdenResuelta(
  AppDatabase db, {
  required int id,
  required String estado,
  int? ventaId,
}) {
  return (db.update(db.ordenesCobroPendientes)..where((o) => o.id.equals(id))).write(
    OrdenesCobroPendientesCompanion(
      estado: Value(estado),
      ventaId: Value(ventaId),
    ),
  );
}

/// Órdenes de esta sesión que quedaron sin resolver (se cortó el polling, o
/// la respuesta del POST nunca llegó) — para mostrar en el Cierre como
/// aviso, nunca para bloquearlo. `sinResolver` es "sigue en 'pendiente' y
/// nunca terminó en una venta".
Future<List<OrdenCobroPendiente>> ordenesSinResolverDeSesion(AppDatabase db, int sesionCajaId) {
  return (db.select(db.ordenesCobroPendientes)
        ..where((o) => o.sesionCajaId.equals(sesionCajaId) & o.estado.equals('pendiente') & o.ventaId.isNull()))
      .get();
}

/// La orden de la Point con la que se cobró [ventaId], si se cobró así (etapa B: para ofrecer la devolución al anularla). Una
/// venta cobrada a mano o en efectivo no tiene orden: esa plata se devuelve desde la app de Mercado Pago.
Future<OrdenCobroPendiente?> ordenCobradaDeVenta(AppDatabase db, int ventaId) {
  return (db.select(db.ordenesCobroPendientes)
        ..where((o) => o.ventaId.equals(ventaId) & o.ordenIdMp.isNotNull() & o.estado.isIn(const ['aprobada', 'devuelta']))
        ..orderBy([(o) => OrderingTerm.desc(o.id)])
        ..limit(1))
      .getSingleOrNull();
}

/// La plata de esa orden ya se le devolvió al cliente por Mercado Pago.
Future<void> marcarOrdenDevuelta(AppDatabase db, int id) {
  return (db.update(db.ordenesCobroPendientes)..where((o) => o.id.equals(id))).write(
    const OrdenesCobroPendientesCompanion(estado: Value('devuelta')),
  );
}

