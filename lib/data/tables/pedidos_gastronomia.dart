import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Pedidos de un local gastronómico (v68, `REGLAS-NEGOCIO.md` §22, `docs/PLAN-GASTRONOMIA.md`). Tabla propia y no
/// `pendientes`: un pedido tiene canal, cocina y entrega, y mezclarlo con los encargues del almacén ensuciaba sus consultas
/// (mismo motivo que `Turnos`). Las reglas viven en `domain/pedido_gastronomico.dart`.
///
/// Se sincroniza: la PC y el celular ven la misma lista.
@DataClassName('PedidoGastronomia')
class PedidosGastronomia extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Número legible y único entre equipos, con el prefijo del equipo (`numero_venta.dart`): "K7-P0042".
  TextColumn get numero => text()();

  /// `CanalPedido.clave`, `EstadoPedido.clave` y `FormaEntrega.clave` (`domain/pedido_gastronomico.dart`).
  TextColumn get canal => text()();
  TextColumn get estado => text()();
  TextColumn get formaEntrega => text().withDefault(const Constant('RETIRO'))();

  /// La persona: alcanza con el nombre; el teléfono es para avisarle por WhatsApp (el del bot llega solo).
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  TextColumn get nombreCliente => text()();
  TextColumn get telefono => text().nullable()();

  /// Envío: adónde y a qué zona, y lo que se le cobra por llevarlo (foto de la zona al tomar el pedido).
  TextColumn get direccion => text().nullable()();
  TextColumn get zona => text().nullable()();
  IntColumn get costoEnvioCentavos => integer().withDefault(const Constant(0))();

  /// Lo pedido, como JSON `[{"gid": <global_id del plato>, "nombre": ..., "cantidad"|"gramos": ..., "precioCentavos": ...}]`:
  /// por `global_id` porque el pedido viaja por la sync, y con el precio del momento, que es el que se le dijo al cliente.
  TextColumn get lineasJson => text()();
  TextColumn get nota => text().nullable()();

  /// Cuándo se le dijo al cliente que va a estar (o llegar), según la cocina al tomarlo.
  DateTimeColumn get horaEstimada => dateTime().nullable()();

  /// Eligió pagar adelantado por Mercado Pago, y si ya llegó ese pago.
  BoolColumn get pagaAdelantado => boolean().withDefault(const Constant(false))();
  BoolColumn get pagado => boolean().withDefault(const Constant(false))();

  /// La venta con que se cobró.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();

  /// El id del pedido en el sitio (`/api/bot/pedidos`), para no bajarlo dos veces y avisarle al bot de un cambio.
  TextColumn get idRemoto => text().nullable()();

  DateTimeColumn get fechaCreacion => dateTime().withDefault(currentDateAndTime)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
