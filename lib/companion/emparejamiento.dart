// Persiste los datos de emparejamiento (IP/puerto/token de la PC, y quién
// está usando el celular) entre aperturas de la companion app — así no hace
// falta escanear el QR ni elegir usuario cada vez.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cliente_companion.dart';
import 'modo_uso.dart';

const _claveConexion = 'companion_conexion';
const _claveUsuarioId = 'companion_usuario_id';
const _claveUsuarioNombre = 'companion_usuario_nombre';
const _claveModoUso = 'companion_modo_uso';

Future<void> guardarConexion(DatosConexion c) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _claveConexion,
    jsonEncode({'ip': c.ip, 'puerto': c.puerto, 'token': c.token}),
  );
}

Future<DatosConexion?> leerConexion() async {
  final prefs = await SharedPreferences.getInstance();
  final texto = prefs.getString(_claveConexion);
  if (texto == null) return null;
  final j = jsonDecode(texto) as Map<String, dynamic>;
  return DatosConexion(
    ip: j['ip'] as String,
    puerto: j['puerto'] as int,
    token: j['token'] as String,
  );
}

Future<void> olvidarConexion() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_claveConexion);
}

Future<void> guardarUsuario(UsuarioCompanion u) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_claveUsuarioId, u.id);
  await prefs.setString(_claveUsuarioNombre, u.nombre);
}

Future<UsuarioCompanion?> leerUsuario() async {
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getInt(_claveUsuarioId);
  final nombre = prefs.getString(_claveUsuarioNombre);
  if (id == null || nombre == null) return null;
  return UsuarioCompanion(id: id, nombre: nombre);
}

Future<void> olvidarUsuario() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_claveUsuarioId);
  await prefs.remove(_claveUsuarioNombre);
}

Future<void> guardarModoUso(ModoUso modo) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_claveModoUso, modo.clave);
}

Future<ModoUso?> leerModoUso() async {
  final prefs = await SharedPreferences.getInstance();
  return ModoUso.desdeClave(prefs.getString(_claveModoUso));
}
