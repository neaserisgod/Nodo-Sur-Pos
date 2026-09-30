// Solo para el spike de la companion app (2026-09-07): corre el servidor
// como proceso standalone para probarlo desde afuera con curl/el navegador,
// simulando lo que haría el celular. No es parte de la app real todavía —
// usa una base en memoria (no la base real de la app), justamente para no
// arriesgar datos reales mientras se prueba a mano.
import 'package:drift/native.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';

Future<void> main() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  final token = await regenerarTokenCompanion(db);

  final server = await iniciarServidorCompanion(db);
  final ips = await direccionesIpLocales();
  // ignore: avoid_print
  print('Escuchando en 0.0.0.0:${server.port}');
  // ignore: avoid_print
  print('IPs locales: $ips');
  // ignore: avoid_print
  print('Token: $token');
  // ignore: avoid_print
  print('Probá: curl -H "$encabezadoToken: $token" http://127.0.0.1:${server.port}/usuarios');
}
