// Servidor manual para probar la companion app contra un emulador Android
// de verdad, sin arriesgar la base real de Bruno. Se corre con
// `flutter test` (no `dart run`) a propósito: `AppDatabase` importa
// `drift_flutter`, que arrastra `dart:ui` — plain `dart run` no puede
// resolver eso, `flutter test` sí (mismo motivo que cualquier test de
// `test/servidor/`). No es un test real (no hace ningún `expect`), es un
// harness que se queda vivo un rato para poder interactuar con él a mano.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';

void main() {
  test(
    'servidor manual con datos de prueba, queda vivo para probar a mano',
    () async {
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
      print('===COMPANION-PRUEBA-LISTA===');
      // ignore: avoid_print
      print('PUERTO=${server.port}');
      // ignore: avoid_print
      print('TOKEN=$token');
      // ignore: avoid_print
      print('USUARIO_ID=$usuarioId');
      // ignore: avoid_print
      print('===FIN===');

      await Future<void>.delayed(const Duration(minutes: 15));
      await server.close();
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
