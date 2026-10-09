import 'package:drift/drift.dart';

/// El concepto (Alquiler, Luz, Internet...). El monto vive aparte, en
/// [GastosFijosMontos], porque cambia de un mes a otro (Regla 12) y conviene
/// guardar el historial en vez de sobrescribir un único campo mutable.
@DataClassName('GastoFijo')
class GastosFijos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 80).unique()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Día del mes en que vence (1–31; en un mes más corto vence el último día). Null = sin fecha cargada. Es fijo como
  /// el concepto, no por mes: el alquiler vence el mismo día todos los meses (El dueño, 2026-10-07).
  IntColumn get diaVencimiento => integer().nullable()();

  /// Identidad de sincronización (v63, El dueño, 2026-10-09: independizar el celular): los fijos se cargan desde la PC o el
  /// celular y viajan entre los dos. Antes eran locales de cada equipo.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

@DataClassName('GastoFijoMonto')
class GastosFijosMontos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get gastoFijoId => integer().references(GastosFijos, #id)();

  /// "YYYY-MM".
  TextColumn get mesAnio => text().withLength(min: 7, max: 7)();
  IntColumn get montoCentavos => integer()();

  /// Ver [GastosFijos.globalId]: el monto de cada mes también viaja (gana el más nuevo).
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {gastoFijoId, mesAnio},
      ];
}
