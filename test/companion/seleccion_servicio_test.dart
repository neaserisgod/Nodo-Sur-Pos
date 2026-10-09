// Selección de servicio con un único ping (fase 3, tercera vuelta —
// reemplaza el circuit breaker por llamada que tenía antes: El dueño,
// 2026-09-17, "la conexión solo detecta 1 vez si la PC está o no").
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/emparejamiento.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/seleccion_servicio.dart';
import 'package:la_plazoleta/companion/servicio_companion_offline.dart';
import 'package:la_plazoleta/data/database.dart' show SesionesDeCajaCompanion;
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('PC alcanzable: resuelve a ClienteCompanion', () async {
    final pc = baseDeTest();
    final token = await regenerarTokenCompanion(pc);
    final server = await iniciarServidorCompanion(pc, puerto: 0);
    addTearDown(server.close);
    addTearDown(pc.close);

    final conexion = DatosConexion(ip: '127.0.0.1', puerto: server.port, token: token);
    final servicio = await resolverServicioCompanion(conexion);

    expect(servicio, isA<ClienteCompanion>());
  });

  test('PC no alcanzable: resuelve a ServicioCompanionOffline, rápido (no espera el ping largo)', () async {
    const conexion = DatosConexion(ip: '127.0.0.1', puerto: 1, token: 'x');
    final local = baseDeTest();
    addTearDown(local.close);

    final arranque = DateTime.now();
    final servicio = await resolverServicioCompanion(conexion, dbLocalDePrueba: local);
    final duracion = DateTime.now().difference(arranque);

    expect(servicio, isA<ServicioCompanionOffline>());
    // Un solo ping, nunca más — `ClienteCompanion.ping` tiene su propio
    // timeout de 4s; si `resolverServicioCompanion` reintentara por su
    // cuenta (el bug que se sacó esta misma vuelta), esto tardaría un
    // múltiplo de eso.
    expect(duracion, lessThan(const Duration(seconds: 4)));
  });

  test('ServicioCompanionOffline: todo delega a PuertoLocal salvo abrirSesion', () async {
    final local = baseDeTest();
    addTearDown(local.close);
    final servicio = ServicioCompanionOffline(PuertoLocal(local), esSoloCelular: () async => false, sincronizarNube: () async => false);

    // Delega de verdad (no un stub vacío): trae el catálogo real de la base
    // local (proveedores sembrados de fábrica).
    final proveedores = await servicio.proveedores();
    expect(proveedores, isNotEmpty);

    // Política especial: con "PC y celular" y sin poder confirmarlo con la nube, no abre una caja propia.
    expect(
      () => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 1000),
      throwsA(isA<ErrorCompanion>().having((e) => e.mensaje, 'mensaje', contains('no se puede saber si la caja ya se abrió'))),
    );
    final sesionesLocales = await local.select(local.sesionesDeCaja).get();
    expect(sesionesLocales, isEmpty);
  });

  test('ServicioCompanionOffline: con "PC y celular" y la PC apagada, abre si la nube confirma que no hay otra (El dueño, 2026-10-09)', () async {
    final local = baseDeTest();
    addTearDown(local.close);
    var sincronizadas = 0;
    final servicio = ServicioCompanionOffline(PuertoLocal(local), esSoloCelular: () async => false, sincronizarNube: () async {
      sincronizadas++;
      return true;
    });
    final usuario = (await servicio.usuarios()).first;

    await servicio.abrirSesion(usuarioId: usuario.id, fondoInicialCentavos: 1000);

    expect(await local.select(local.sesionesDeCaja).get(), hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(sincronizadas, 2, reason: 'una antes de abrir (confirmar) y otra después (que la PC la vea ya)');
  });

  test('ServicioCompanionOffline: si la nube trajo una caja abierta de la PC, no abre otra', () async {
    final local = baseDeTest();
    addTearDown(local.close);
    final usuarioId = (await local.select(local.usuarios).get()).first.id;
    final servicio = ServicioCompanionOffline(PuertoLocal(local), esSoloCelular: () async => false, sincronizarNube: () async {
      // Lo que bajó de la nube: la caja que abrió la PC.
      if ((await local.select(local.sesionesDeCaja).get()).isEmpty) {
        await local.into(local.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 500));
      }
      return true;
    });

    expect(
      () => servicio.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 1000),
      throwsA(isA<ErrorCompanion>().having((e) => e.mensaje, 'mensaje', contains('Ya hay una caja abierta'))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await local.select(local.sesionesDeCaja).get(), hasLength(1));
  });

  test('ServicioCompanionOffline: con "Solo celular" abre la caja sobre la base local', () async {
    final local = baseDeTest();
    addTearDown(local.close);
    final servicio = ServicioCompanionOffline(PuertoLocal(local), esSoloCelular: () async => true);
    final usuario = (await servicio.usuarios()).first;

    final id = await servicio.abrirSesion(usuarioId: usuario.id, fondoInicialCentavos: 1000);

    final sesiones = await local.select(local.sesionesDeCaja).get();
    expect(sesiones.single.id, id);
    expect(sesiones.single.fondoInicialCentavos, 1000);
    expect(sesiones.single.globalId, isNotNull, reason: 'tiene que viajar por la sync');
  });

  test('ServicioCompanionOffline: con "Solo celular" no abre una segunda caja', () async {
    final local = baseDeTest();
    addTearDown(local.close);
    final servicio = ServicioCompanionOffline(PuertoLocal(local), esSoloCelular: () async => true);
    final usuario = (await servicio.usuarios()).first;
    await servicio.abrirSesion(usuarioId: usuario.id, fondoInicialCentavos: 1000);

    expect(
      () => servicio.abrirSesion(usuarioId: usuario.id, fondoInicialCentavos: 2000),
      throwsA(isA<ErrorCompanion>().having((e) => e.mensaje, 'mensaje', contains('Ya hay una caja abierta'))),
    );
    expect(await local.select(local.sesionesDeCaja).get(), hasLength(1));
  });

  test('esSoloCelularGuardado sigue el modo elegido y, sin modo, si hay una PC emparejada', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await esSoloCelularGuardado(), isTrue, reason: 'sin PC ni modo: el celular solo');

    await guardarModoUso(ModoUso.pcYCelular);
    expect(await esSoloCelularGuardado(), isFalse);

    await guardarModoUso(ModoUso.soloCelular);
    expect(await esSoloCelularGuardado(), isTrue);

    SharedPreferences.setMockInitialValues({});
    await guardarConexion(const DatosConexion(ip: '10.0.0.2', puerto: 8080, token: 't'));
    expect(await esSoloCelularGuardado(), isFalse, reason: 'instalación vieja con PC emparejada');
  });
}
