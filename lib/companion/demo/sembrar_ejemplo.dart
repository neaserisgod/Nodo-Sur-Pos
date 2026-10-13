// Cargar un negocio de ejemplo en una cuenta de verdad (El dueño, 2026-10-13: "armame un seed para la cuenta… es una
// barbería", para grabar los reels con la app real: notificaciones del bot y seña por link incluidas). Es la misma siembra de
// la demo (`semilla_demo.dart`), corrida sobre la base del equipo: todo entra por los repositorios, así que viaja por la sync
// como cualquier dato.
//
// Escondido a propósito (7 toques en el título de Más). Con la base vacía se carga directo; si ya tiene turnos, ventas o
// cajas, se pregunta antes con un "Cargar igual" en rojo (El dueño, 2026-10-13: su cuenta de prueba ya tenía datos y el
// bloqueo la frenaba). Nunca se carga dos veces: los servicios quedarían repetidos.

import '../../data/database.dart';
import 'semilla_demo.dart';

enum EstadoParaEjemplo {
  /// Sin turnos, ventas ni cajas: se carga sin preguntar.
  vacia,

  /// Tiene datos: se puede cargar igual, pero hay que confirmarlo.
  conDatos,

  /// El negocio de ejemplo ya se cargó en esta base.
  yaCargado,
}

/// Cómo está [db] para recibir [negocio].
Future<EstadoParaEjemplo> estadoParaEjemplo(AppDatabase db, {NegocioDemo negocio = NegocioDemo.barberia}) async {
  final nombres = {for (final s in negocio.servicios) s.nombre};
  final servicios = await (db.select(db.productos)..where((p) => p.esServicio.equals(true))).get();
  if (nombres.every((n) => servicios.any((s) => s.nombre == n))) return EstadoParaEjemplo.yaCargado;
  final vacia = (await (db.select(db.turnos)..limit(1)).get()).isEmpty &&
      (await (db.select(db.ventas)..limit(1)).get()).isEmpty &&
      (await (db.select(db.sesionesDeCaja)..limit(1)).get()).isEmpty;
  return vacia ? EstadoParaEjemplo.vacia : EstadoParaEjemplo.conDatos;
}

/// Carga [negocio] en [db]. Con datos, solo si [aunqueTengaDatos]; si ya estaba cargado, nunca. Devuelve si cargó.
Future<bool> sembrarEjemploEnCuenta(
  AppDatabase db, {
  NegocioDemo negocio = NegocioDemo.barberia,
  bool aunqueTengaDatos = false,
  DateTime? ahora,
}) async {
  final estado = await estadoParaEjemplo(db, negocio: negocio);
  if (estado == EstadoParaEjemplo.yaCargado) return false;
  if (estado == EstadoParaEjemplo.conDatos && !aunqueTengaDatos) return false;
  await sembrarNegocioDemo(db, negocio, ahora: ahora);
  return true;
}
