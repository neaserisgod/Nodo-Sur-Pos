import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Turnos de un negocio de servicios (v66, `REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4). Tabla propia y no
/// `pendientes`: un turno tiene hora y duración, y mezclarlos con los encargues ensuciaba las consultas del almacén. Reusa la
/// seña y el "convertir en venta" de los encargues (`domain/sena.dart`, `registrarVenta(turnoId:)`).
///
/// Se sincroniza: la Agenda la ven todos los equipos del negocio.
class Turnos extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// El servicio (`productos.es_servicio`). Null si se borró: el turno conserva [servicioNombre] y [duracionMinutos].
  IntColumn get servicioId => integer().nullable().references(Productos, #id)();

  /// Foto del servicio al dar el turno: si después cambia el nombre o la duración, este turno no se corre.
  TextColumn get servicioNombre => text()();
  IntColumn get duracionMinutos => integer()();

  DateTimeColumn get inicio => dateTime()();

  /// La persona: alcanza con el nombre; el teléfono es opcional (el del bot llega solo). Al confirmarse queda guardada como
  /// cliente ([clienteId]).
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  TextColumn get nombreCliente => text()();
  TextColumn get telefono => text().nullable()();

  /// Quién atiende. Null: el negocio de una sola persona, o "cualquiera".
  IntColumn get profesionalId => integer().nullable().references(Usuarios, #id)();

  /// `EstadoTurno.clave` (`domain/turnos.dart`).
  TextColumn get estado => text().withDefault(const Constant('CONFIRMADO'))();

  /// La seña que pide el servicio (lo que se le pidió al cliente). 0 = sin seña.
  IntColumn get senaPedidaCentavos => integer().withDefault(const Constant(0))();

  /// La seña que ya pagó, por qué caja entró, y si ya entró a una caja (§21: una seña que llega sin caja abierta entra como
  /// ingreso en la próxima caja que se abra en este equipo).
  IntColumn get senaCentavos => integer().withDefault(const Constant(0))();
  BoolColumn get senaEsEfectivo => boolean().withDefault(const Constant(false))();
  BoolColumn get senaEnCaja => boolean().withDefault(const Constant(true))();

  /// Hasta cuándo se espera la seña antes de liberar el horario (turnos del bot).
  DateTimeColumn get senaVence => dateTime().nullable()();

  /// 'APP' (cargado a mano) o 'BOT' (lo dio el bot de WhatsApp).
  TextColumn get origen => text().withDefault(const Constant('APP'))();

  /// El id del turno en el sitio (`/api/bot/turnos`), para no bajarlo dos veces y avisarle al bot de un cambio.
  TextColumn get idRemoto => text().nullable()();

  TextColumn get nota => text().nullable()();

  /// La venta con que se cobró.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();

  DateTimeColumn get fechaCreacion => dateTime().withDefault(currentDateAndTime)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
