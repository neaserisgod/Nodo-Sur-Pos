// Sync instantánea por wifi (2026-09-28): `/companion/eventos` avisa en el
// momento cuando cambia la base de la PC, y un pedido del celular que
// modifica algo marca "lo cambió el celular" para las pantallas de la PC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/notificador_cambios.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import '../helpers/base_para_tests.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late HttpServer server;
  late String token;

  setUp(() async {
    db = baseDeTest();
    notificadorCambios = NotificadorCambios(db);
    token = await regenerarTokenCompanion(db);
    server = await iniciarServidorCompanion(db, puerto: 0);
  });

  tearDown(() async {
    await server.close(force: true);
    notificadorCambios?.cerrar();
    notificadorCambios = null;
    await db.close();
  });

  Future<StreamIterator<String>> conectar() async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final pedido = await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/companion/eventos'));
    pedido.headers.set(encabezadoToken, token);
    final respuesta = await pedido.close();
    expect(respuesta.statusCode, 200);
    expect(respuesta.headers.contentType?.mimeType, 'text/event-stream');
    return StreamIterator(
      respuesta.transform(utf8.decoder).transform(const LineSplitter()).where((l) => l.startsWith('data:')),
    );
  }

  test('sin token no se puede escuchar', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final pedido = await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/companion/eventos'));
    final respuesta = await pedido.close();
    expect(respuesta.statusCode, 401);
  });

  test('al conectarse llega la versión actual, y un cambio en la base llega al instante', () async {
    final eventos = await conectar();
    expect(await eventos.moveNext().timeout(const Duration(seconds: 2)), isTrue); // el saludo inicial

    final reloj = Stopwatch()..start();
    await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    expect(await eventos.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    reloj.stop();

    expect(eventos.current, contains('"version"'));
    // Un aviso, no un sondeo: tiene que llegar en menos de medio segundo.
    expect(reloj.elapsedMilliseconds, lessThan(500));
  });

  test('un pedido del celular que modifica algo avisa a las pantallas de la PC', () async {
    final avisos = <void>[];
    final sub = notificadorCambios!.cambiosDelCelular.listen(avisos.add);
    addTearDown(sub.cancel);

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final pedido = await http.postUrl(Uri.parse('http://127.0.0.1:${server.port}/usuarios'));
    pedido.headers.set(encabezadoToken, token);
    pedido.headers.contentType = ContentType.json;
    pedido.write(jsonEncode({'nombre': 'Marta'}));
    final respuesta = await pedido.close();
    await respuesta.drain<void>();
    expect(respuesta.statusCode, lessThan(300));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(avisos, hasLength(1));
  });

  test('una consulta (GET) no avisa: la PC no recarga sus pantallas por una lectura', () async {
    final avisos = <void>[];
    final sub = notificadorCambios!.cambiosDelCelular.listen(avisos.add);
    addTearDown(sub.cancel);

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final pedido = await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/usuarios'));
    pedido.headers.set(encabezadoToken, token);
    final respuesta = await pedido.close();
    await respuesta.drain<void>();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(avisos, isEmpty);
  });
}
