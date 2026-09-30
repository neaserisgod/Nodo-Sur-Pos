// Decide UNA sola vez, con un ping corto, si esta apertura de pantalla le
// habla a la PC por HTTP o resuelve contra la base local — fase 3 del
// rediseño "companion sin depender del escritorio" (El dueño, 2026-09-17: "la
// conexión solo detecta 1 vez si la PC está o no" — antes cada método
// reintentaba la PC por su cuenta con un timeout propio, así que una PC
// caída volvía lenta CADA acción, no solo la primera; ahora se decide una
// vez, acá, y de ahí en más se usa esa decisión derecho, sin más esperas).
//
// No hay reintento automático a mitad de pantalla: si la PC se cae después
// de haber elegido `ClienteCompanion`, esa pantalla se entera recién al
// fallar una llamada real (mismo `ErrorCompanion` de siempre). Volver a
// entrar a la pantalla (o el pull-to-refresh de Inicio) vuelve a preguntar.

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'puerto_local.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';

Future<ServicioCompanion> resolverServicioCompanion(
  DatosConexion conexion, {
  @visibleForTesting AppDatabase? dbLocalDePrueba,
}) async {
  final alcanzable = await ClienteCompanion.ping(conexion.ip, conexion.puerto);
  if (alcanzable) return ClienteCompanion(conexion);
  return ServicioCompanionOffline(PuertoLocal(dbLocalDePrueba ?? baseLocalCompanion()));
}
