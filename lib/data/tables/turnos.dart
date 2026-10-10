import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Turnos de un negocio de servicios (v66, `REGLAS-NEGOCIO.md` §21). Tabla propia y no dentro de `pendientes` (El dueño,
/// 2026-10-10): reusan la lógica de la seña y de convertir en venta de los encargues, sin mezclarse en las consultas del
/// almacén. Viaja por la sync.
class Turnos extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// El cliente, si quedó guardado (§21: al confirmarse el turno queda como cliente). [nombreCliente] siempre está, así el
  /// turno se lee aunque el cliente todavía no llegó por la sync.
  IntColumn get clienteId => integer().nullable().references(Clientes, #id)();
  TextColumn get nombreCliente => text()();
  TextColumn get telefono => text().nullable()();

  /// El servicio (un producto con `es_servicio`). [duracionMinutos] es la del servicio al anotarlo: si después cambia, el
  /// turno ya dado no se corre.
  IntColumn get servicioId => integer().nullable().references(Productos, #id)();
  IntColumn get duracionMinutos => integer()();

  /// Quién atiende (un usuario de la app). Null: el negocio tiene una sola persona.
  IntColumn get profesionalId => integer().nullable().references(Usuarios, #id)();

  DateTimeColumn get inicio => dateTime()();

  /// `EstadoTurno.clave` (`domain/agenda.dart`).
  TextColumn get estado => text().withDefault(const Constant('confirmado'))();

  /// 'app' | 'whatsapp'.
  TextColumn get origen => text().withDefault(const Constant('app'))();

  /// La seña (§21, como la de un encargue: `domain/sena.dart`): entró a la caja como ingreso y al cobrar se aplica.
  IntColumn get senaCentavos => integer().withDefault(const Constant(0))();
  BoolColumn get senaEsEfectivo => boolean().withDefault(const Constant(true))();

  /// La venta que lo cobró.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();

  TextColumn get nota => text().nullable()();

  /// Quién lo anotó.
  IntColumn get usuarioId => integer().references(Usuarios, #id)();
  DateTimeColumn get creadoEn => dateTime().withDefault(currentDateAndTime)();

  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
