// Selección de servicio con un único ping (fase 3, tercera vuelta —
// reemplaza el circuit breaker por llamada que tenía antes: El dueño,
// 2026-09-17, "la conexión solo detecta 1 vez si la PC está o no").
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/seleccion_servicio.dart';
import 'package:la_plazoleta/companion/servicio_companion_offline.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
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
    final servicio = ServicioCompanionOffline(PuertoLocal(local));

    // Delega de verdad (no un stub vacío): trae el catálogo real de la base
    // local (proveedores sembrados de fábrica).
    final proveedores = await servicio.proveedores();
    expect(proveedores, isNotEmpty);

    // Política especial: nunca abre una caja propia offline.
    expect(
      () => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 1000),
      throwsA(
        isA<ErrorCompanion>().having(
          (e) => e.mensaje,
          'mensaje',
          contains('No se puede abrir'),
        ),
      ),
    );
    final sesionesLocales = await local.select(local.sesionesDeCaja).get();
    expect(sesionesLocales, isEmpty);
  });
}
