// Caché offline de "Cierres" (El dueño, 2026-09-13: "quiero la pantalla nueva
// de cierres con caché offline") — mismo mecanismo que `emparejamiento.dart`
// (shared_preferences, un JSON como texto), para poder ver la última copia
// conocida de los cierres reales aunque el celular esté fuera del local o
// la app de escritorio esté cerrada. NUNCA sincronización en vivo desde
// lejos (eso necesitaría un servidor en la nube, contra el "todo local" del
// proyecto): es una foto de la última vez que sí hubo conexión.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cliente_companion.dart';

const _claveCierres = 'companion_cierres_cache';
const _claveFecha = 'companion_cierres_cache_fecha';

/// Guarda la lista tal cual vino del servidor, más cuándo se guardó (para
/// poder avisar "esto es de hace X" si después se muestra sin conexión).
Future<void> guardarCierresEnCache(List<SesionCerradaCompanion> cierres) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _claveCierres,
    jsonEncode([for (final c in cierres) c.aJson()]),
  );
  await prefs.setString(_claveFecha, DateTime.now().toIso8601String());
}

/// null si nunca se guardó nada (primera vez que se abre esta pantalla sin
/// haber tenido conexión todavía).
Future<({List<SesionCerradaCompanion> cierres, DateTime fecha})?>
leerCierresDeCache() async {
  final prefs = await SharedPreferences.getInstance();
  final texto = prefs.getString(_claveCierres);
  final fechaTexto = prefs.getString(_claveFecha);
  if (texto == null || fechaTexto == null) return null;
  final lista = (jsonDecode(texto) as List)
      .cast<Map<String, dynamic>>()
      .map(SesionCerradaCompanion.desdeJson)
      .toList();
  return (cierres: lista, fecha: DateTime.parse(fechaTexto));
}
