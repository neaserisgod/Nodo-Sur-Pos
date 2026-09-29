import 'package:drift/drift.dart';

/// El concepto (Alquiler, Luz, Internet...). El monto vive aparte, en
/// [GastosFijosMontos], porque cambia de un mes a otro (Regla 12) y conviene
/// guardar el historial en vez de sobrescribir un único campo mutable.
@DataClassName('GastoFijo')
class GastosFijos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 80).unique()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
}

@DataClassName('GastoFijoMonto')
class GastosFijosMontos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get gastoFijoId => integer().references(GastosFijos, #id)();

  /// "YYYY-MM".
  TextColumn get mesAnio => text().withLength(min: 7, max: 7)();
  IntColumn get montoCentavos => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {gastoFijoId, mesAnio},
      ];
}
