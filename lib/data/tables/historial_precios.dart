import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';

/// Una fila por cada cambio de precio o costo de un producto (Regla 14). Se
/// guardan los cuatro valores en cada fila (no solo el que cambió) para que
/// cada fila sea una foto completa del estado en ese momento, sin tener que
/// reconstruirlo mirando filas anteriores.
class HistorialDePrecios extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productoId => integer().references(Productos, #id)();

  IntColumn get precioCentavos => integer().nullable()();
  IntColumn get costoCentavos => integer().nullable()();
  IntColumn get precioPorKiloCentavos => integer().nullable()();
  IntColumn get costoPorKiloCentavos => integer().nullable()();

  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  /// Identidad de sincronización — ver el comentario de cabecera de la
  /// migración v29→v30 en `database.dart`. Append-only (una fila de
  /// historial nunca se edita), [fecha] ya sirve de cursor de sync.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
}
