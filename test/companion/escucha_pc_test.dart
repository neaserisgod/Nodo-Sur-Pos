// Sync instantánea por wifi, de punta a punta (2026-09-28): una PC con su
// servidor real y un "celular" (otra base en memoria) escuchando sus
// avisos. Lo que cambia en la PC tiene que aparecer solo en el celular en
// menos de un segundo, y lo que escribe el celular tiene que llegar a la PC.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cambios_companion.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/escucha_pc.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/notificador_cambios.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase pc;
  late AppDatabase celular;
  late HttpServer server;
  late EscuchaPc escucha;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pc = baseDeTest();
    celular = baseDeTest();
    notificadorCambios = NotificadorCambios(pc);
    final token = await regenerarTokenCompanion(pc);
    server = await iniciarServidorCompanion(pc, puerto: 0);
    escucha = EscuchaPc(DatosConexion(ip: '127.0.0.1', puerto: server.port, token: token), celular)..iniciar();
    // Que termine la conexión y la sincronización inicial.
    await _esperarHasta(() async => escucha.conectada);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  tearDown(() async {
    escucha.detener();
    await server.close(force: true);
    notificadorCambios?.cerrar();
    notificadorCambios = null;
    await pc.close();
    await celular.close();
  });

  test('una categoría creada en la PC aparece sola en el celular en menos de un segundo', () async {
    var avisos = 0;
    final sub = avisosCambiosCompanion.listen((_) => avisos++);
    addTearDown(sub.cancel);

    final reloj = Stopwatch()..start();
    await crearCategoria(pc, 'Fiambres importados');
    await _esperarHasta(() async {
      final cats = await celular.select(celular.categorias).get();
      return cats.any((c) => c.nombre == 'Fiambres importados');
    });
    reloj.stop();

    expect(reloj.elapsedMilliseconds, lessThan(1000));
    // Y las pantallas del celular se enteran (para refrescarse solas).
    expect(avisos, greaterThan(0));
  });

  test('con todo quieto no hay avisos: ni bucle de sincronización ni pantallas que se resetean', () async {
    // Bug real (2026-09-28, "el celular me resetea la pantalla todo el
    // rato"): el borde de la sync (`>=`) se re-subía en cada vuelta, la PC lo
    // tomaba como un cambio y avisaba, y el celular sincronizaba de nuevo.
    var avisosCelular = 0;
    var avisosPc = 0;
    final subCel = avisosCambiosCompanion.listen((_) => avisosCelular++);
    final subPc = notificadorCambios!.cambiosDelCelular.listen((_) => avisosPc++);
    addTearDown(subCel.cancel);
    addTearDown(subPc.cancel);

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(avisosCelular, 0);
    expect(avisosPc, 0);
  });

  test('después de un cambio, los avisos se calman (no quedan dando vueltas)', () async {
    var avisos = 0;
    final sub = avisosCambiosCompanion.listen((_) => avisos++);
    addTearDown(sub.cancel);

    await crearCategoria(pc, 'Una sola vez');
    await _esperarHasta(() async => avisos > 0);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final despuesDelCambio = avisos;
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(despuesDelCambio, lessThanOrEqualTo(2));
    expect(avisos, despuesDelCambio);
  });

  test('lo que escribe el celular en su base llega solo a la PC', () async {
    await crearCategoria(celular, 'Cargada en el celular');
    await _esperarHasta(() async {
      final cats = await pc.select(pc.categorias).get();
      return cats.any((c) => c.nombre == 'Cargada en el celular');
    });
  });
}

/// Espera hasta [limite] a que [condicion] se cumpla; falla si no.
Future<void> _esperarHasta(Future<bool> Function() condicion, {Duration limite = const Duration(seconds: 3)}) async {
  final fin = DateTime.now().add(limite);
  while (DateTime.now().isBefore(fin)) {
    if (await condicion()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('No pasó en ${limite.inMilliseconds} ms');
}
