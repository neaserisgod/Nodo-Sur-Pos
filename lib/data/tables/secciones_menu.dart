import 'package:drift/drift.dart';

/// Qué pantallas de gestión aparecen en el menú de la pantalla de venta y en
/// qué orden (fase 8) — "Cerrar caja" e "Imprimir ticket" quedan fijos en el
/// código a propósito, son acciones core, no secciones opcionales.
@DataClassName('SeccionMenu')
class SeccionesMenu extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Identificador estable de la pantalla (no cambia aunque el usuario
  /// renombre nada) — ver `claveSeccion` en la capa de datos para el mapeo a
  /// cada pantalla real.
  TextColumn get clave => text().withLength(min: 1, max: 40).unique()();

  TextColumn get etiqueta => text().withLength(min: 1, max: 60)();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();
  IntColumn get orden => integer()();
}
