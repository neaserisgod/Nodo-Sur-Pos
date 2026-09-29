import 'package:drift/drift.dart';

import 'catalogo.dart';
import 'usuarios.dart';
import 'ventas.dart';

/// Todo cambio de stock deja un movimiento registrado (Regla 8): venta,
/// ajuste o devolución, nunca un número que se corrige sin rastro.
@DataClassName('MovimientoStock')
class MovimientosDeStock extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productoId => integer().references(Productos, #id)();
  IntColumn get ventaId => integer().nullable().references(Ventas, #id)();
  IntColumn get usuarioId => integer().references(Usuarios, #id)();

  /// 'VENTA' | 'AJUSTE' | 'DEVOLUCION'.
  TextColumn get tipo => text()();

  // Unidades. Null si el producto es pesable.
  IntColumn get cantidad => integer().nullable()();
  IntColumn get stockAnterior => integer().nullable()();
  IntColumn get stockPosterior => integer().nullable()();

  // Gramos. Null si el producto no es pesable.
  IntColumn get gramos => integer().nullable()();
  IntColumn get gramosAnterior => integer().nullable()();
  IntColumn get gramosPosterior => integer().nullable()();

  TextColumn get motivo => text().nullable()();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();

  /// Identidad de sincronización (companion Android sin depender del
  /// escritorio) — ver `lib/domain/stock.dart` y el comentario de cabecera
  /// de la migración v29→v30 en `database.dart`. Esta es justamente la
  /// tabla que hace posible mergear dos dispositivos vendiendo el mismo
  /// producto offline sin que uno le pise el conteo al otro: es append-only
  /// (nunca se actualiza un movimiento ya grabado), así que dos movimientos
  /// con `globalId` distintos son dos hechos reales que los dos pasaron.
  /// [fecha] ya sirve como cursor de sync, no hace falta `actualizadoEn`.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
}
