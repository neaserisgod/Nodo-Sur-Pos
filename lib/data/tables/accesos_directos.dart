import 'package:drift/drift.dart';

import 'catalogo.dart';

/// La grilla de directos de la pantalla de venta (cigarrillos con su tecla).
/// Configurable a propósito: las marcas que más se venden cambian, y no
/// tiene sentido recompilar la app por eso. Se siembran 6 posiciones fijas y
/// vacías al crear la base; el producto y la tecla de cada una se cargan
/// desde la pantalla de venta (todavía no hay una fase de configuración
/// dedicada, así que la edición vive ahí por ahora).
///
/// "Varios" NO es una fila de esta tabla: es un botón fijo aparte, siempre
/// presente (Regla 5/9 lo tratan como una pieza estructural, no como "una
/// marca más"), con su propio atajo fijo en el código (Alt+V).
@DataClassName('AccesoDirecto')
class AccesosDirectos extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 0..5. Define el orden de la grilla, no cambia con la configuración.
  IntColumn get posicion => integer()();

  /// La letra o dígito de "Alt+" seguido de esta tecla. Null = posición sin
  /// asignar todavía.
  /// Única entre las posiciones asignadas: dos slots con la misma tecla
  /// serían un atajo ambiguo.
  TextColumn get tecla => text().nullable().unique()();

  IntColumn get productoId =>
      integer().nullable().references(Productos, #id)();
}
