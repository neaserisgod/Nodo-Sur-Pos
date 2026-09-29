// Gestión de usuarios (fase 8, Regla 18). Sin autenticación real (CLAUDE.md:
// "sin backend, sin red, sin autenticación") — esto es solo el catálogo de
// nombres entre los que se elige al abrir caja, nunca borrado real (misma
// convención que productos/categorías/proveedores).

import 'package:drift/drift.dart';

import 'database.dart';
import 'identidad_sync.dart';

Future<List<Usuario>> listarUsuarios(AppDatabase db) => db.select(db.usuarios).get();

Future<List<Usuario>> listarUsuariosActivos(AppDatabase db) {
  return (db.select(db.usuarios)..where((u) => u.activo.equals(true))).get();
}

/// Bug real encontrado 2026-09-19 (al llevar Configuración a la companion):
/// esta función y las tres de abajo nunca seteaban `globalId`/`actualizadoEn`
/// — cualquier usuario creado o editado en el escritorio desde la migración
/// v31→v32 nunca sincronizaba de verdad (`cambiosDesde` filtra
/// `global_id IS NOT NULL`). Mismo patrón ya correcto en
/// `repositorio_productos.dart::actualizarMarkupCategoria`.
Future<int> crearUsuario(AppDatabase db, String nombre) {
  return db.into(db.usuarios).insert(
        UsuariosCompanion.insert(
          nombre: nombre,
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> renombrarUsuario(AppDatabase db, int id, String nombreNuevo) {
  return (db.update(db.usuarios)..where((u) => u.id.equals(id))).write(
        UsuariosCompanion(nombre: Value(nombreNuevo), actualizadoEn: Value(DateTime.now())),
      );
}

Future<void> desactivarUsuario(AppDatabase db, int id) {
  return (db.update(db.usuarios)..where((u) => u.id.equals(id))).write(
        UsuariosCompanion(activo: const Value(false), actualizadoEn: Value(DateTime.now())),
      );
}

Future<void> activarUsuario(AppDatabase db, int id) {
  return (db.update(db.usuarios)..where((u) => u.id.equals(id))).write(
        UsuariosCompanion(activo: const Value(true), actualizadoEn: Value(DateTime.now())),
      );
}
