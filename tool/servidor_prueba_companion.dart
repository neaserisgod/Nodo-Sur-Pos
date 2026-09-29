// Solo para probar la companion app de punta a punta sin arriesgar la base
// real de Bruno (C:\Users\Bruno\Documents\la_plazoleta.sqlite): levanta el
// mismo servidor que usa la app de escritorio, pero contra una base en
// memoria con datos de prueba. Nunca tocar el .exe real / la base real para
// esto.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';

Future<void> main() async {
  final db = AppDatabase(NativeDatabase.memory());

  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno (prueba)'));
  await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Fernet Branca',
          codigoBarras: const Value('7791234567890'),
          precioCentavos: const Value(1200000),
          costoCentavos: const Value(800000),
          stock: const Value(7),
        ),
      );
  await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Queso barra',
          esPesable: const Value(true),
          precioPorKiloCentavos: const Value(850000),
          costoPorKiloCentavos: const Value(600000),
          stockGramos: const Value(3000),
        ),
      );

  final token = await regenerarTokenCompanion(db);

  final server = await iniciarServidorCompanion(db, puerto: 8099);
  // ignore: avoid_print
  print('=== Servidor de prueba companion ===');
  // ignore: avoid_print
  print('Escuchando en 0.0.0.0:${server.port}');
  // ignore: avoid_print
  print('Desde el emulador Android, la IP de la PC es: 10.0.2.2');
  // ignore: avoid_print
  print('Token: $token');
  // ignore: avoid_print
  print('Usuario de prueba: Bruno (prueba), id=$usuarioId');
  // ignore: avoid_print
  print('Productos de prueba: "Fernet Branca" (stock 7 un.), "Queso barra" (3000 g)');
}
