// Gestión de medios de pago (fase 8) — solo renombrar/activar/desactivar
// los 2 que ya existen. Sin alta de medios nuevos a propósito: todo el
// dominio (recargo de cigarrillos, redondeo, `ComposicionPago`) asume
// exactamente efectivo/virtual/mixto, no una lista abierta — agregar un
// tercer medio real requeriría repensar esa base primero.

import 'package:drift/drift.dart';

import 'database.dart';

Future<List<MedioDePago>> listarMediosDePago(AppDatabase db) {
  return (db.select(db.mediosDePago)..orderBy([(m) => OrderingTerm.asc(m.orden)])).get();
}

/// `nombre` es unique a nivel de esquema — sin este chequeo, renombrar a un
/// nombre ya usado por el otro medio (ej. "Efectivo" → "Mercado Pago") tira
/// una excepción cruda de sqlite sin capturar, igual que el bug real ya
/// encontrado y corregido para `codigoBarras` en `repositorio_productos.dart`.
Future<void> renombrarMedioDePago(AppDatabase db, int id, String nombreNuevo) async {
  final existente = await (db.select(
    db.mediosDePago,
  )..where((m) => m.nombre.equals(nombreNuevo) & m.id.equals(id).not())).getSingleOrNull();
  if (existente != null) {
    throw ArgumentError('Ya existe un medio de pago con ese nombre: "$nombreNuevo".');
  }
  await (db.update(db.mediosDePago)..where((m) => m.id.equals(id)))
      .write(MediosDePagoCompanion(nombre: Value(nombreNuevo), actualizadoEn: Value(DateTime.now())));
}

Future<void> desactivarMedioDePago(AppDatabase db, int id) {
  return (db.update(db.mediosDePago)..where((m) => m.id.equals(id))).write(MediosDePagoCompanion(activo: const Value(false), actualizadoEn: Value(DateTime.now())));
}

Future<void> activarMedioDePago(AppDatabase db, int id) {
  return (db.update(db.mediosDePago)..where((m) => m.id.equals(id))).write(MediosDePagoCompanion(activo: const Value(true), actualizadoEn: Value(DateTime.now())));
}
