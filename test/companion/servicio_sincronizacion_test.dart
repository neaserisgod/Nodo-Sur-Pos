// Orquestación de sincronización del lado del celular (fase 2 del
// rediseño "companion sin depender del escritorio") — un servidor real
// (igual que `test/servidor/servidor_companion_test.dart`) hace de PC, y
// `sincronizarConPc` se prueba contra una base "celular" propia pasada por
// `dbDePrueba` (no la real de `base_local.dart`, que abre con
// `path_provider` y no tiene sentido en este entorno de test).
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/servicio_sincronizacion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase pc;
  late AppDatabase celular;
  late ClienteCompanion cliente;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pc = AppDatabase(NativeDatabase.memory());
    celular = AppDatabase(NativeDatabase.memory());
    final token = await regenerarTokenCompanion(pc);
    final server = await iniciarServidorCompanion(pc, puerto: 0);
    addTearDown(server.close);
    cliente = ClienteCompanion(
      DatosConexion(ip: '127.0.0.1', puerto: server.port, token: token),
    );
  });

  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  test('trae a la base del celular una fila creada en la PC', () async {
    await crearCategoria(pc, 'Fiambres importados');

    final ok = await sincronizarConPc(cliente, db: celular);
    expect(ok, isTrue);

    final sincronizadas =
        await (celular.select(celular.categorias)..where((c) => c.globalId.isNotNull())).get();
    expect(sincronizadas.length, 1);
    expect(sincronizadas.single.nombre, 'Fiambres importados');
  });

  test('un segundo sync sin cambios nuevos no duplica nada', () async {
    await crearCategoria(pc, 'Fiambres importados');

    await sincronizarConPc(cliente, db: celular);
    await sincronizarConPc(cliente, db: celular);

    final sincronizadas =
        await (celular.select(celular.categorias)..where((c) => c.globalId.isNotNull())).get();
    expect(sincronizadas.length, 1);
  });

  test('el cursor persiste entre llamadas: la segunda solo trae lo nuevo', () async {
    await crearCategoria(pc, 'Fiambres importados');
    await sincronizarConPc(cliente, db: celular);

    await crearCategoria(pc, 'Otra categoría nueva');
    await sincronizarConPc(cliente, db: celular);

    final sincronizadas =
        await (celular.select(celular.categorias)..where((c) => c.globalId.isNotNull())).get();
    expect(sincronizadas.map((c) => c.nombre).toSet(), {
      'Fiambres importados',
      'Otra categoría nueva',
    });
  });

  test('si la PC no responde, devuelve false en vez de tirar una excepción', () async {
    final clienteRoto = ClienteCompanion(
      const DatosConexion(ip: '127.0.0.1', puerto: 1, token: 'lo que sea'),
    );
    final ok = await sincronizarConPc(clienteRoto, db: celular);
    expect(ok, isFalse);
  });
}
