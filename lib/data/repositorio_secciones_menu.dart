// Qué pantallas de gestión aparecen en el menú de la pantalla de venta y en
// qué orden (fase 8). "Cerrar caja" e "Imprimir ticket" no pasan por acá:
// son acciones core, fijas en el código.

import 'package:drift/drift.dart';

import 'database.dart';

Future<List<SeccionMenu>> listarSecciones(AppDatabase db) {
  return (db.select(db.seccionesMenu)..orderBy([(s) => OrderingTerm.asc(s.orden)])).get();
}

Future<List<SeccionMenu>> listarSeccionesVisibles(AppDatabase db) {
  return (db.select(db.seccionesMenu)
        ..where((s) => s.visible.equals(true))
        ..orderBy([(s) => OrderingTerm.asc(s.orden)]))
      .get();
}

Future<void> ocultarSeccion(AppDatabase db, int id) {
  return (db.update(db.seccionesMenu)..where((s) => s.id.equals(id))).write(const SeccionesMenuCompanion(visible: Value(false)));
}

Future<void> mostrarSeccion(AppDatabase db, int id) {
  return (db.update(db.seccionesMenu)..where((s) => s.id.equals(id))).write(const SeccionesMenuCompanion(visible: Value(true)));
}

/// Aplica un orden nuevo completo: [idsEnOrden] es la lista de ids de TODAS
/// las secciones, en el orden que deben quedar.
Future<void> reordenarSecciones(AppDatabase db, List<int> idsEnOrden) async {
  for (var i = 0; i < idsEnOrden.length; i++) {
    await (db.update(db.seccionesMenu)..where((s) => s.id.equals(idsEnOrden[i])))
        .write(SeccionesMenuCompanion(orden: Value(i)));
  }
}
