// Gestión de usuarios (fase 8, Regla 18). Sin autenticación real (CLAUDE.md:
// "sin backend, sin red, sin autenticación") — esto es solo el catálogo de
// nombres entre los que se elige al abrir caja, nunca borrado real (misma
// convención que productos/categorías/proveedores).

import 'package:drift/drift.dart';

import 'database.dart';
import 'identidad_sync.dart';
import '../domain/usuarios_repetidos.dart';
import 'normalizacion_texto.dart';

/// Los perfiles, sin repetidos: si dos tienen el mismo nombre (sin mayúsculas ni acentos) son la misma persona y se muestra
/// uno solo (`domain/usuarios_repetidos.dart`), activo si alguno lo está. TODA lista de perfiles para elegir sale de acá.
Future<List<Usuario>> listarUsuarios(AppDatabase db) async {
  final todos = await db.select(db.usuarios).get();
  final grupos = agruparRepetidos([for (final u in todos) (id: u.id, nombre: u.nombre, globalId: u.globalId, activo: u.activo)]);
  if (grupos.isEmpty) return todos;
  final ocultos = {for (final g in grupos) ...g.repetidos};
  final activoDe = {for (final g in grupos) g.queda: g.activo};
  return [
    for (final u in todos)
      if (!ocultos.contains(u.id)) activoDe.containsKey(u.id) ? u.copyWith(activo: activoDe[u.id]) : u,
  ];
}

Future<List<Usuario>> listarUsuariosActivos(AppDatabase db) async => [
  for (final u in await listarUsuarios(db))
    if (u.activo) u,
];

/// Junta los perfiles repetidos (mismo nombre = misma persona, El dueño 2026-10-13): todo lo que apunta a un repetido (ventas,
/// cajas, movimientos, turnos…) pasa al que queda, y el que queda está activo si alguno lo estaba. Las filas repetidas NO se
/// borran: algo todavía puede apuntarles (una venta que llega de otro equipo, el perfil guardado en un celular), y la próxima
/// pasada la mueve. Todos los equipos eligen el mismo que queda, así que no hace falta sincronizar nada de esto: cada uno lo
/// hace solo. Devuelve cuántos repetidos había.
Future<int> unificarUsuariosRepetidos(AppDatabase db) async {
  final todos = await db.select(db.usuarios).get();
  final grupos = agruparRepetidos([for (final u in todos) (id: u.id, nombre: u.nombre, globalId: u.globalId, activo: u.activo)]);
  if (grupos.isEmpty) return 0;
  final columnas = await _columnasQueApuntanAUsuarios(db);
  await db.transaction(() async {
    for (final g in grupos) {
      final repetidos = g.repetidos.join(', ');
      for (final (tabla, columna) in columnas) {
        // OR IGNORE: si una restricción única no deja mover una fila, esa queda apuntando al repetido (que sigue existiendo).
        await db.customStatement('UPDATE OR IGNORE $tabla SET $columna = ${g.queda} WHERE $columna IN ($repetidos)');
      }
      // Sin tocar `actualizado_en`: no es un cambio para mandar, cada equipo llega solo al mismo resultado.
      await db.customStatement('UPDATE usuarios SET activo = ${g.activo ? 1 : 0} WHERE id = ${g.queda}');
    }
  });
  return grupos.fold<int>(0, (n, g) => n + g.repetidos.length);
}

/// Todas las columnas de la base que apuntan a `usuarios`, leídas del esquema: una tabla nueva queda cubierta sola.
Future<List<(String, String)>> _columnasQueApuntanAUsuarios(AppDatabase db) async {
  final tablas = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").get();
  return [
    for (final t in tablas)
      for (final fk in await db.customSelect("SELECT * FROM pragma_foreign_key_list('${t.data['name']}')").get())
        if (fk.data['table'] == 'usuarios') (t.data['name'] as String, fk.data['from'] as String),
  ];
}

/// Bug real encontrado 2026-09-19 (al llevar Configuración a la companion):
/// esta función y las tres de abajo nunca seteaban `globalId`/`actualizadoEn`
/// — cualquier usuario creado o editado en el escritorio desde la migración
/// v31→v32 nunca sincronizaba de verdad (`cambiosDesde` filtra
/// `global_id IS NOT NULL`). Mismo patrón ya correcto en
/// `repositorio_productos.dart::actualizarMarkupCategoria`.
///
/// Si ya hay un perfil con ese nombre (sin mayúsculas ni acentos), es la misma persona: devuelve ese en vez de crear otro.
Future<int> crearUsuario(AppDatabase db, String nombre) async {
  final buscado = normalizarTexto(nombre.trim());
  final mismo = [for (final u in await listarUsuarios(db)) if (normalizarTexto(u.nombre.trim()) == buscado) u].firstOrNull;
  if (mismo != null) {
    // Darlo de alta de nuevo con el mismo nombre es volver a tenerlo: si estaba desactivado, vuelve.
    if (!mismo.activo) await activarUsuario(db, mismo.id);
    return mismo.id;
  }
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
