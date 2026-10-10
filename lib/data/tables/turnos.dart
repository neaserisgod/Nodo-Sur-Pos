import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Un turno de la agenda (v67, `REGLAS-NEGOCIO.md` §21, `lib/domain/turnos.dart`). Viaja por la sync: el celular, otro
/// celular y, en la etapa 5, el bot de WhatsApp escriben en la misma agenda.
@DataClassName('FilaTurno')
class Turnos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clienteId => integer().references(Clientes, #id)();

  /// El servicio (un producto con `esServicio`).
  IntColumn get servicioId => integer().references(Productos, #id)();

  /// Quién lo atiende, con el módulo "Varios profesionales". Null: la agenda del negocio.
  IntColumn get profesionalId => integer().nullable().references(Usuarios, #id)();

  DateTimeColumn get inicio => dateTime()();

  /// Lo que dura, copiado del servicio al anotarlo: cambiar la duración del servicio no mueve los turnos ya dados.
  IntColumn get duracionMinutos => integer()();

  /// `EstadoTurno.clave`: 'pendiente' | 'confirmado' | 'llego' | 'cobrado' | 'novino' | 'cancelado'.
  TextColumn get estado => text().withDefault(const Constant('confirmado'))();

  /// `OrigenTurno.clave`: 'app' | 'whatsapp'.
  TextColumn get origen => text().withDefault(const Constant('app'))();

  /// La seña que dejó, ya en la caja como ingreso (Regla 21, como la de un encargue). 0: sin seña.
  IntColumn get senaCentavos => integer().withDefault(const Constant(0))();
  BoolColumn get senaEsEfectivo => boolean().withDefault(const Constant(true))();

  /// La venta con que se cobró.
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();

  TextColumn get nota => text().nullable()();
  DateTimeColumn get creadoEn => dateTime().withDefault(currentDateAndTime)();

  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
