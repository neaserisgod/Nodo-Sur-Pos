import 'package:drift/drift.dart';

/// Multiusuario sin contraseñas (Regla 18): un selector de nombre al abrir
/// la app. No está en la lista de tablas de CLAUDE.md — es un agujero del
/// documento, no una omisión a propósito: sin esta tabla no hay de dónde
/// sacar el selector, y "cada venta, edición y arqueo registra quién lo
/// hizo" necesita algo a lo que apuntar.
class Usuarios extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nombre => text().withLength(min: 1, max: 60)();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();

  /// Identidad de sincronización (migración v31→v32, el dueño, 2026-09-18: "no
  /// debería tener que escanear ya, es innecesario") — hasta acá, `usuarios`
  /// había quedado deliberadamente afuera de la migración v29→v30
  /// ("autoridad exclusiva del escritorio"), pero sacar el emparejamiento
  /// obligatorio de la companion dejó "¿quién sos?" sin de dónde sacar la
  /// lista sin PC. Mismas tres columnas y mismo motivo que
  /// `tables/catalogo.dart` (`Categorias`/`Proveedores`): sin `.unique()`
  /// acá porque SQLite no permite agregar una columna `UNIQUE` con `ALTER
  /// TABLE ... ADD COLUMN` — la unicidad la da un índice aparte
  /// (`_crearIndicesUnicosDeSincronizacion` en `database.dart`).
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}
