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

  /// Milésimas de un insumo (v65): lo que se compró, se usó o se contó, y el stock antes y después. Mismo esquema que los
  /// gramos de un pesable.
  IntColumn get milesimas => integer().nullable()();
  IntColumn get milesimasAnterior => integer().nullable()();
  IntColumn get milesimasPosterior => integer().nullable()();

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

/// La parte del stock de cada producto que NO sale de sus movimientos (v67, El dueño 2026-10-13: "el stock subió y yo no lo
/// subí"): lo que tenía al crearse (un alta con stock inicial, una importación) o de antes de que existieran los movimientos.
/// En cualquier equipo, el stock de un producto es siempre `base + suma de sus movimientos`.
///
/// Por qué existe: un equipo que bajaba todo de cero (un celular nuevo, un negocio agregado, el navegador) recibía cada producto
/// con el stock que ya tenía en el otro equipo Y además todos sus movimientos, y los volvía a sumar: el stock se duplicaba. Con la
/// base, al recibirla se recalcula `base + movimientos` y queda bien, también en los equipos que ya se habían desfasado.
///
/// La escribe SOLO el equipo donde nació el producto (`productos.origen_dispositivo`; los de antes de la sync, la PC): ese
/// equipo nunca recibió el producto por la sync, así que su cuenta es siempre la buena. Una por producto; no cambia nunca.
@DataClassName('BaseDeStock')
class BasesDeStock extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productoId => integer().references(Productos, #id)();
  IntColumn get stockBase => integer().nullable()();
  IntColumn get gramosBase => integer().nullable()();
  IntColumn get milesimasBase => integer().nullable()();
  /// El mismo `global_id` que el producto: una base por producto, aunque dos equipos la escriban.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
