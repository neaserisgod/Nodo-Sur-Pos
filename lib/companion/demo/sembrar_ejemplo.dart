// Cargar un negocio de ejemplo en una cuenta de verdad (El dueño, 2026-10-13: "armame un seed para la cuenta… es una
// barbería", para grabar los reels con la app real: notificaciones del bot y seña por link incluidas). Es la misma siembra de
// la demo (`semilla_demo.dart`), corrida sobre la base del equipo: todo entra por los repositorios, así que viaja por la sync
// como cualquier dato.
//
// Escondido a propósito (7 toques en el título de Más) y solo con la base sin turnos, ventas ni cajas: los datos son
// inventados y no tienen que poder mezclarse nunca con los de un negocio que ya trabaja.

import '../../data/database.dart';
import 'semilla_demo.dart';

/// Si [db] no tiene nada que un negocio de ejemplo pueda pisar o ensuciar. Un negocio recién configurado (nombre, rubro y
/// su primer servicio) todavía cuenta como vacío: es justo el estado en que queda una cuenta nueva.
Future<bool> baseVaciaParaEjemplo(AppDatabase db) async =>
    (await (db.select(db.turnos)..limit(1)).get()).isEmpty &&
    (await (db.select(db.ventas)..limit(1)).get()).isEmpty &&
    (await (db.select(db.sesionesDeCaja)..limit(1)).get()).isEmpty;

/// Carga [negocio] en [db] si está vacía. Devuelve false (sin tocar nada) si no lo está.
Future<bool> sembrarEjemploEnCuenta(AppDatabase db, {NegocioDemo negocio = NegocioDemo.barberia, DateTime? ahora}) async {
  if (!await baseVaciaParaEjemplo(db)) return false;
  await sembrarNegocioDemo(db, negocio, ahora: ahora);
  return true;
}
