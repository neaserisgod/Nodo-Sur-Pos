// Id estable de este celular — se genera una sola vez y se guarda, para que
// `origen_dispositivo` de las filas que algún día escriba `PuertoLocal` (fase
// 3 del rediseño de sincronización) identifique siempre al mismo aparato,
// aunque se reinstale la companion. Mismo mecanismo de persistencia que ya
// usa `emparejamiento.dart` para la conexión y el usuario elegido.

import 'package:shared_preferences/shared_preferences.dart';

import '../data/identidad_sync.dart';

const _claveIdDispositivo = 'companion_id_dispositivo';

/// Lee el id guardado o genera uno nuevo la primera vez. Llamar una sola vez
/// al arrancar la companion (`companion_app.dart`), antes de cualquier
/// operación que pueda escribir en la base local.
Future<String> idDispositivoEstable() async {
  final prefs = await SharedPreferences.getInstance();
  final existente = prefs.getString(_claveIdDispositivo);
  if (existente != null) return existente;

  final nuevo = 'android-${generarGlobalId()}';
  await prefs.setString(_claveIdDispositivo, nuevo);
  return nuevo;
}
