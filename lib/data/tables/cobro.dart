import 'package:drift/drift.dart';

import 'caja.dart';
import 'ventas.dart';

/// Cobro por terminal Point (Fase 12). Cada fila se inserta ANTES de llamar
/// a la API de Mercado Pago (`POST /v1/orders`) — nunca después — porque
/// [idempotencyKey] y [externalReference] tienen que existir en disco antes
/// del POST para poder reintentar con la misma clave si la respuesta se
/// pierde a mitad de camino (Regla de Fase 12: nunca doble cobro por un
/// corte de conexión). Si la app se cierra o se corta la conexión con esto
/// ya sembrado pero sin resolver, [estado] queda en 'pendiente' y
/// `ordenesSinResolverDeSesion` la saca a la luz en el Cierre — nunca se
/// asume que salió bien ni que salió mal.
@DataClassName('OrdenCobroPendiente')
class OrdenesCobroPendientes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// UUID generado acá, no un id de venta (la venta todavía no existe en
  /// este momento — recién se graba si el pago se aprueba).
  TextColumn get externalReference => text().unique()();

  /// Va en el header `X-Idempotency-Key` de la request. Reintentar el
  /// mismo POST con esta misma clave le pide a Mercado Pago la MISMA
  /// orden en vez de crear una nueva.
  TextColumn get idempotencyKey => text()();

  /// 'qr' | 'debit_card'.
  TextColumn get canal => text()();

  IntColumn get montoCentavos => integer()();

  IntColumn get sesionCajaId => integer().references(SesionesDeCaja, #id)();

  /// Null hasta que el POST responde con éxito y la API confirma que creó
  /// la orden — recién ahí hay algo que consultar con `GET /v1/orders/{id}`.
  TextColumn get ordenIdMp => text().nullable()();

  /// 'pendiente' (recién creada, o la respuesta se perdió) | 'aprobada' |
  /// 'rechazada' | 'cancelada' (Bruno la canceló desde el diálogo).
  TextColumn get estado => text().withDefault(const Constant('pendiente'))();

  DateTimeColumn get creadaEn => dateTime().withDefault(currentDateAndTime)();

  /// Se completa solo si [estado] termina en 'aprobada': la venta real
  /// que este cobro terminó generando.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();
}
