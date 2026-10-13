// El perfil del celular sale de la cuenta (2026-10-02): se reutiliza el del mismo nombre, o se crea; nunca se elige de una lista.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/emparejamiento.dart';
import 'package:la_plazoleta/companion/google_en_celular.dart';
import 'package:la_plazoleta/companion/pantalla_entrar_con_cuenta.dart';
import 'package:la_plazoleta/companion/perfil_por_cuenta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/cuentas_del_celular.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('resolverPerfilDeCuenta', () {
    late AppDatabase db;
    late PuertoLocal puerto;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = baseDeTest();
      puerto = PuertoLocal(db);
    });
    tearDown(() => db.close());

    test('reutiliza el perfil del mismo nombre, sin importar mayúsculas ni acentos, y lo deja guardado', () async {
      final id = await puerto.crearUsuarioNuevo('María Gómez');
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'm@x.com', nombre: 'maria gomez', rol: 'employee'), servicio: puerto);
      expect(u.id, id);
      expect((await leerUsuario())!.id, id);
      expect((await puerto.usuarios()).where((x) => x.nombre.toLowerCase().contains('mar')), hasLength(1), reason: 'no duplicó el perfil');
    });

    test('si no existe lo crea con el nombre de la cuenta', () async {
      final antes = (await puerto.usuarios()).length;
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'nuevo@x.com', nombre: 'Lucas Pérez'), servicio: puerto);
      expect((await puerto.usuarios()).length, antes + 1);
      expect(u.nombre, 'Lucas Pérez');
      expect((await leerUsuario())!.nombre, 'Lucas Pérez');
    });

    test('una cuenta sin nombre usa la parte del mail antes de la @', () async {
      final u = await resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'sinnombre@x.com', nombre: '  '), servicio: puerto);
      expect(u.nombre, 'sinnombre');
    });

    test('un perfil desactivado por el dueño no se reactiva solo: se avisa y no se guarda nada', () async {
      final id = await puerto.crearUsuarioNuevo('Marta');
      await puerto.alternarActivoUsuarioExistente(id, false);
      await expectLater(
        resolverPerfilDeCuenta(perfil: const PerfilDeCuenta(email: 'marta@x.com', nombre: 'Marta'), servicio: puerto),
        throwsA(isA<PerfilDesactivado>()),
      );
      expect(await leerUsuario(), isNull);
    });
  });

  group('PantallaEntrarConCuenta', () {
    late AppDatabase db;
    late PuertoLocal puerto;
    var entro = false;

    setUp(() {
      entro = false;
      SharedPreferences.setMockInitialValues({});
    });

    Future<SyncNubeCompanion> armar(
      WidgetTester t, {
      required bool vinculada,
      required Future<http.Response> Function(http.Request) servidor,
      PedirCuentaGoogle? google,
    }) async {
      db = (await t.runAsync(() async => baseDeTest()))!;
      usarBaseLocalDeTest(db);
      puerto = PuertoLocal(db);
      final almacen = AlmacenCuentaEnMemoria();
      if (vinculada) {
        await almacen.guardar(const CuentaVinculada(token: 'tok', email: 'marta@x.com', idDispositivo: 'd', nombreDispositivo: 'Celular', vence: 99));
      }
      final sync = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: MockClient(servidor)),
        abrirNavegador: (_) async {},
        db: db,
        pedirCuentaGoogle: google ?? (_) async => fail('no tenía que pedir una cuenta de Google'),
      );
      addTearDown(() {
        sync.servicio.detener();
        sync.conmutador.cerrar();
        db.close();
      });
      return sync;
    }

    Future<void> abrir(WidgetTester t, SyncNubeCompanion sync, {IndiceCuentas? cuentas, Future<void> Function(String id)? irA}) async {
      t.view.physicalSize = const Size(400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        theme: TemaCompanion.claro,
        home: PantallaEntrarConCuenta(
          sync: sync,
          servicio: () async => puerto,
          alEntrar: (_) => entro = true,
          leerCuentas: cuentas == null ? null : () async => cuentas,
          irACuentaGuardada: irA,
        ),
      ));
      await _asentar(t);
    }

    http.Response yoOk() => http.Response('{"email":"marta@x.com","name":"Marta Gómez","role":"employee","orgId":1,"branchId":2}', 200, headers: {'content-type': 'application/json'});

    testWidgets('con la cuenta ya vinculada entra solo: toma el perfil de la cuenta y no muestra ninguna lista', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => yoOk());
      await abrir(t, sync);
      expect(entro, isTrue);
      expect((await t.runAsync(() => leerUsuario()))!.nombre, 'Marta Gómez');
      expect(find.text('¿Quién sos?'), findsNothing);
    });

    testWidgets('sin cuenta pide entrar con ella: no hay selector de perfil y no se entra', (t) async {
      final sync = await armar(t, vinculada: false, servidor: (r) async => fail('no tenía que llamar a nada'));
      await abrir(t, sync);
      expect(find.byKey(const Key('entrar_con_cuenta')), findsOneWidget);
      expect(find.text('¿Quién sos?'), findsNothing);
      expect(entro, isFalse);
    });

    testWidgets('si la sacaron del negocio (401) lo dice y ofrece entrar de nuevo, sin dejarla pasar', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => http.Response('{"error":"no_device"}', 401));
      await abrir(t, sync);
      expect(entro, isFalse);
      expect(find.byKey(const Key('entrar_error')), findsOneWidget);
      expect(find.byKey(const Key('entrar_con_cuenta')), findsOneWidget);
      expect(find.byKey(const Key('entrar_reintentar')), findsNothing, reason: 'reintentar con el mismo token no sirve');
    });

    testWidgets('un perfil desactivado en el POS no entra y lo explica', (t) async {
      final sync = await armar(t, vinculada: true, servidor: (r) async => yoOk());
      final id = (await t.runAsync(() => puerto.crearUsuarioNuevo('Marta Gómez')))!;
      await t.runAsync(() => puerto.alternarActivoUsuarioExistente(id, false));
      await abrir(t, sync);
      expect(entro, isFalse);
      expect(find.textContaining('desactivado'), findsOneWidget);
    });

    group('entrar con la cuenta de Google del teléfono (sin navegador)', () {
      final pedidos = <http.Request>[];
      http.Response jsonOk(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
      Future<http.Response> sitio(http.Request r, {bool elegir = false}) async {
        pedidos.add(r);
        if (r.url.path == '/api/device/google' && r.method == 'GET') return jsonOk({'clientId': 'web.apps.googleusercontent.com'});
        if (r.url.path == '/api/device/google') {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          if (b['idToken'] != 'id-token-de-marta') return http.Response('{"error":"google_invalido"}', 401);
          if (elegir && b['branchId'] == null) {
            return jsonOk({
              'elegir': true,
              'orgs': [
                {'id': 1, 'name': 'La Plazoleta', 'branches': [{'id': 2, 'name': 'Sucursal principal'}, {'id': 3, 'name': 'Centro'}]},
              ],
            });
          }
          return jsonOk({'token': 'tok-nuevo', 'email': 'marta@x.com', 'deviceId': b['deviceId'], 'expiresAt': 99});
        }
        if (r.url.path == '/api/device/me') return yoOk();
        return fail('pedido inesperado: ${r.method} ${r.url}');
      }

      setUp(pedidos.clear);

      // Al quedar vinculado arranca la sync por internet, con sus esperas: se frena y se dejan vencer antes de terminar.
      Future<void> frenarSync(WidgetTester t, SyncNubeCompanion sync) async {
        sync.servicio.detener();
        await t.pump(const Duration(seconds: 30));
      }

      testWidgets('elige la cuenta, el sitio la confirma y entra con su perfil', (t) async {
        String? pedidoCon;
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (clientId) async {
          pedidoCon = clientId;
          return 'id-token-de-marta';
        });
        await abrir(t, sync);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(pedidoCon, 'web.apps.googleusercontent.com', reason: 'el client ID lo da el sitio');
        expect(entro, isTrue);
        expect((await t.runAsync(() => sync.cuenta()))!.token, 'tok-nuevo');
        expect((await t.runAsync(() => leerUsuario()))!.nombre, 'Marta Gómez');
        await frenarSync(t, sync);
      });

      testWidgets('si trabaja en dos sucursales pregunta en cuál, y entra en la elegida', (t) async {
        final sync = await armar(t, vinculada: false, servidor: (r) => sitio(r, elegir: true), google: (_) async => 'id-token-de-marta');
        await abrir(t, sync);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(find.text('¿En qué negocio entrás?'), findsOneWidget);
        expect(entro, isFalse);
        await t.tap(find.text('La Plazoleta · Centro'));
        await _asentar(t);
        expect(entro, isTrue);
        final ultimo = jsonDecode(pedidos.lastWhere((r) => r.url.path == '/api/device/google' && r.method == 'POST').body);
        expect(ultimo['branchId'], 3);
        expect(ultimo['orgId'], 1);
        await frenarSync(t, sync);
      });

      testWidgets('si Google no anda en este teléfono lo dice y ofrece el navegador', (t) async {
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (_) async => throw const GoogleNoDisponible('sin servicios'));
        await abrir(t, sync);
        expect(find.byKey(const Key('entrar_con_navegador')), findsNothing);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(find.byKey(const Key('entrar_error')), findsOneWidget);
        expect(find.byKey(const Key('entrar_con_navegador')), findsOneWidget);
        expect(entro, isFalse);
      });

      testWidgets('cerrar el selector sin elegir no entra ni muestra error, pero deja el navegador a mano', (t) async {
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (_) async => null);
        await abrir(t, sync);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(entro, isFalse);
        expect(find.byKey(const Key('entrar_error')), findsNothing);
        expect(find.byKey(const Key('entrar_con_navegador')), findsOneWidget);
        expect(pedidos.where((r) => r.method == 'POST'), isEmpty);
      });

      testWidgets('el sitio sin entrar con Google (versión vieja): ofrece el navegador sin abrir el selector', (t) async {
        final sync = await armar(t, vinculada: false, servidor: (r) async => http.Response('', 404));
        await abrir(t, sync);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(find.byKey(const Key('entrar_con_navegador')), findsOneWidget);
      });
    });

    group('varias cuentas en el celular', () {
      // El mismo negocio y sucursal que devuelve yoOk (orgId 1, branchId 2).
      const marta = CuentaDelCelular(id: 'm', email: 'marta@x.com', nombre: 'Marta Gómez', negocio: 1, sucursal: 2, nombreNegocio: 'La Plazoleta');
      http.Response jsonOk(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
      Future<http.Response> sitio(http.Request r) async {
        if (r.url.path == '/api/device/google' && r.method == 'GET') return jsonOk({'clientId': 'web'});
        if (r.url.path == '/api/device/google') return jsonOk({'token': 't', 'email': 'marta@x.com', 'deviceId': 'd', 'expiresAt': 9});
        if (r.url.path == '/api/device/me') return yoOk();
        return fail('pedido inesperado: ${r.url}');
      }

      testWidgets('agregando un negocio pide siempre la lista y deja crear uno nuevo con su nombre', (t) async {
        final posts = <Map<String, dynamic>>[];
        final sync = await armar(t, vinculada: false, google: (_) async => 'x', servidor: (r) async {
          if (r.url.path == '/api/device/google' && r.method == 'GET') return jsonOk({'clientId': 'web'});
          if (r.url.path == '/api/device/google') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            posts.add(b);
            if (b['nuevoNegocio'] == null) {
              return jsonOk({
                'elegir': true,
                'orgs': [
                  {'id': 1, 'name': 'Almacén', 'branches': [{'id': 2, 'name': 'Sucursal principal'}]},
                ],
              });
            }
            return jsonOk({'token': 't', 'email': 'marta@x.com', 'deviceId': 'd', 'expiresAt': 9});
          }
          if (r.url.path == '/api/device/me') {
            return jsonOk({'email': 'marta@x.com', 'name': 'Marta Gómez', 'role': 'owner', 'orgId': 7, 'branchId': 8, 'orgName': 'Barbería', 'branchName': 'Sucursal principal'});
          }
          return fail('pedido inesperado: ${r.url}');
        });
        await abrir(t, sync, cuentas: const IndiceCuentas(guardadas: [marta]));
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(posts.single['elegirSiempre'], isTrue, reason: 'agregando, aunque tenga un solo negocio');
        expect(find.text('Almacén'), findsOneWidget);
        await t.tap(find.byKey(const Key('crear_negocio')));
        await _asentar(t);
        await t.enterText(find.byKey(const Key('nombre_negocio')), 'Barbería');
        await t.pump();
        await t.tap(find.text('Crear'));
        await _asentar(t);
        expect(posts.last['nuevoNegocio'], 'Barbería');
        expect(entro, isTrue);
        final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
        expect(prefs.getString('companion_negocio_de_la_cuenta'), contains('Barbería'), reason: 'para mostrarlo en la lista de negocios');
        sync.servicio.detener();
        await t.pump(const Duration(seconds: 30));
      });

      testWidgets('agregando otra cuenta se puede volver a la guardada sin entrar', (t) async {
        final sync = await armar(t, vinculada: false, servidor: (r) async => fail('no tenía que llamar a nada'));
        final idas = <String>[];
        await abrir(t, sync, cuentas: const IndiceCuentas(guardadas: [marta]), irA: (id) async => idas.add(id));
        await t.tap(find.byKey(const Key('volver_a_cuenta')));
        await _asentar(t);
        expect(idas, ['m']);
      });

      testWidgets('sin otra cuenta guardada (o con la cuenta activa) no hay "volver"', (t) async {
        final sync = await armar(t, vinculada: false, servidor: (r) async => fail('no tenía que llamar a nada'));
        await abrir(t, sync, cuentas: const IndiceCuentas(activa: marta));
        expect(find.byKey(const Key('volver_a_cuenta')), findsNothing);
      });

      testWidgets('entrar en un negocio que ya está guardado con el mismo mail ofrece ir a ese en vez de tenerlo dos veces', (t) async {
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (_) async => 'x');
        final idas = <String>[];
        await abrir(t, sync, cuentas: const IndiceCuentas(guardadas: [marta]), irA: (id) async => idas.add(id));
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(find.text('La Plazoleta ya está en este celular'), findsOneWidget);
        await t.tap(find.text('Ir a La Plazoleta'));
        await _asentar(t);
        expect(idas, ['m']);
        expect(entro, isFalse);
        sync.servicio.detener();
        await t.pump(const Duration(seconds: 30));
      });

      testWidgets('si NO está agregando (la cuenta ya vivía acá, p. ej. venció la sesión), nunca ofrece descartarla', (t) async {
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (_) async => 'x');
        await abrir(
          t,
          sync,
          cuentas: const IndiceCuentas(activa: CuentaDelCelular(id: 'yo', email: 'marta@x.com'), guardadas: [marta]),
          irA: (_) async => fail('no tenía que descartar nada'),
        );
        expect(find.byKey(const Key('volver_a_cuenta')), findsNothing);
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        expect(find.textContaining('ya está en este celular'), findsNothing);
        expect(entro, isTrue);
        sync.servicio.detener();
        await t.pump(const Duration(seconds: 30));
      });

      testWidgets('si prefiere otro negocio, se cierra la sesión repetida y sigue en la pantalla de entrar', (t) async {
        final sync = await armar(t, vinculada: false, servidor: sitio, google: (_) async => 'x');
        await abrir(t, sync, cuentas: const IndiceCuentas(guardadas: [marta]), irA: (_) async => fail('no tenía que irse'));
        await t.tap(find.byKey(const Key('entrar_con_cuenta')));
        await _asentar(t);
        await t.tap(find.text('Entrar en otro negocio'));
        await _asentar(t);
        expect(await t.runAsync(() => sync.cuenta()), isNull);
        expect(entro, isFalse);
        expect(find.byKey(const Key('entrar_con_cuenta')), findsOneWidget);
        await t.pump(const Duration(seconds: 30));
      });
    });
  });
}
