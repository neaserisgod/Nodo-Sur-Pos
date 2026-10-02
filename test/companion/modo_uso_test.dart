// Modo de uso del celular: PC y celular, o solo celular (`modo_uso.dart`, `flujo_modo_uso.dart`).

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/conmutador_sync.dart';
import 'package:la_plazoleta/companion/emparejamiento.dart';
import 'package:la_plazoleta/companion/escucha_pc.dart';
import 'package:la_plazoleta/companion/flujo_modo_uso.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_elegir_modo.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/servidor_sync_falso.dart';


/// La app de prueba, con las animaciones apagadas (las partículas del encabezado nunca terminan de animar y
/// `pumpAndSettle` no volvería): igual que "reducir animaciones" en el celular.
Widget _app(Widget home) => MaterialApp(
  theme: TemaCompanion.claro,
  builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('qué modo corresponde', () {
    test('lo guardado manda', () {
      for (final m in ModoUso.values) {
        expect(resolverModoUso(guardado: m, tieneConexion: true, tieneUsuario: true), m);
        expect(resolverModoUso(guardado: m, tieneConexion: false, tieneUsuario: false), m);
      }
    });

    test('una instalación vieja con PC emparejada sigue en "PC y celular"', () {
      expect(resolverModoUso(guardado: null, tieneConexion: true, tieneUsuario: true), ModoUso.pcYCelular);
      expect(resolverModoUso(guardado: null, tieneConexion: true, tieneUsuario: false), ModoUso.pcYCelular);
    });

    test('una instalación vieja sin PC pero ya usada sigue como "solo celular"', () {
      expect(resolverModoUso(guardado: null, tieneConexion: false, tieneUsuario: true), ModoUso.soloCelular);
    });

    test('una instalación nueva no tiene modo: hay que preguntar', () {
      expect(resolverModoUso(guardado: null, tieneConexion: false, tieneUsuario: false), isNull);
    });

    test('las claves guardadas son estables y una desconocida no es ningún modo', () {
      expect(ModoUso.pcYCelular.clave, 'pc');
      expect(ModoUso.soloCelular.clave, 'celular');
      expect(ModoUso.desdeClave('pc'), ModoUso.pcYCelular);
      expect(ModoUso.desdeClave('celular'), ModoUso.soloCelular);
      expect(ModoUso.desdeClave('otra'), isNull);
      expect(ModoUso.desdeClave(null), isNull);
    });
  });

  group('guardado', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('se guarda y se lee; sin nada guardado es null', () async {
      expect(await leerModoUso(), isNull);
      await guardarModoUso(ModoUso.soloCelular);
      expect(await leerModoUso(), ModoUso.soloCelular);
      await guardarModoUso(ModoUso.pcYCelular);
      expect(await leerModoUso(), ModoUso.pcYCelular);
    });
  });

  group('la pantalla de elegir', () {
    Future<List<ModoUso>> abrir(WidgetTester tester, {ModoUso? actual}) async {
      final elegidos = <ModoUso>[];
      await tester.pumpWidget(_app(PantallaElegirModo(actual: actual, alElegir: (_, m) => elegidos.add(m))));
      await tester.pumpAndSettle();
      return elegidos;
    }

    testWidgets('primer arranque: pregunta y ofrece las dos opciones, sin botón de volver', (tester) async {
      await abrir(tester);
      expect(find.text('¿Cómo vas a usar el sistema?'), findsOneWidget);
      expect(find.text('Tengo PC y celular'), findsOneWidget);
      expect(find.text('Solo uso el celular'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('tocar una opción avisa cuál', (tester) async {
      final elegidos = await abrir(tester);
      await tester.tap(find.byKey(const Key('modo-solo-celular')));
      await tester.tap(find.byKey(const Key('modo-pc-y-celular')));
      expect(elegidos, [ModoUso.soloCelular, ModoUso.pcYCelular]);
    });

    testWidgets('al cambiar desde Gestión: tiene título propio y marca el modo actual', (tester) async {
      await abrir(tester, actual: ModoUso.soloCelular);
      expect(find.text('Modo de uso'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('¿Cómo vas a usar el sistema?'), findsNothing);
    });
  });

  group('dejar el celular como único sistema', () {
    late SyncNubeCompanion sync;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final almacen = AlmacenCuentaEnMemoria();
      await almacen.guardar(const CuentaVinculada(
        token: 'tok-cel', email: 'a@b.com', idDispositivo: 'android-1', nombreDispositivo: 'Celular', vence: 99));
      final servidor = ServidorSyncFalso();
      final db = baseDeTest();
      addTearDown(db.close);
      sync = syncNubeCompanion = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
        abrirNavegador: (_) async {},
        db: db,
      );
    });

    tearDown(() {
      sync.servicio.detener();
      sync.conmutador.cerrar();
      syncNubeCompanion = null;
      escuchaPcCompanion = null;
    });

    test('olvida la PC, guarda el modo y la nube arranca sola (hay cuenta)', () async {
      await guardarConexion(const DatosConexion(ip: '192.168.0.5', puerto: 8099, token: 't'));
      await guardarModoUso(ModoUso.pcYCelular);
      sync.conmutador.definirPc(emparejada: true);

      await aplicarModoSoloCelular();

      expect(await leerConexion(), isNull);
      expect(await leerModoUso(), ModoUso.soloCelular);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sync.conmutador.modo.value, ModoSync.nube, reason: 'sin PC no hay a quién esperar');
    });

    test('sin cuenta vinculada queda solo en el celular', () async {
      await sync.almacen.borrar();
      await aplicarModoSoloCelular();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sync.conmutador.modo.value, ModoSync.local);
      expect(await leerModoUso(), ModoUso.soloCelular);
    });

    test('no toca al usuario elegido', () async {
      await guardarUsuario(const UsuarioCompanion(id: 1, nombre: 'Ana'));
      await aplicarModoSoloCelular();
      expect((await leerUsuario())?.nombre, 'Ana');
    });
  });
  group('el primer arranque, de punta a punta', () {
    late SyncNubeCompanion sync;

    Future<void> armar({required bool conCuenta}) async {
      SharedPreferences.setMockInitialValues({});
      final almacen = AlmacenCuentaEnMemoria();
      if (conCuenta) {
        await almacen.guardar(const CuentaVinculada(
          token: 'tok-cel', email: 'ana@x.com', idDispositivo: 'android-1', nombreDispositivo: 'Celular', vence: 99));
      }
      final servidor = ServidorSyncFalso();
      final db = baseDeTest();
      addTearDown(db.close);
      sync = syncNubeCompanion = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
        abrirNavegador: (_) async {},
        db: db,
      );
      addTearDown(() {
        sync.servicio.detener();
        sync.conmutador.cerrar();
        syncNubeCompanion = null;
      });
    }

    Future<void> arrancar(WidgetTester tester) async {
      await tester.pumpWidget(_app(pantallaDeElegirModoInicial()));
      await tester.pumpAndSettle();
    }

    testWidgets('"solo celular": guarda el modo y ofrece vincular la cuenta antes de entrar', (tester) async {
      await armar(conCuenta: false);
      await arrancar(tester);

      await tester.tap(find.byKey(const Key('modo-solo-celular')));
      await tester.pumpAndSettle();

      expect(await leerModoUso(), ModoUso.soloCelular);
      expect(find.text('Cuenta y sincronización'), findsOneWidget);
      expect(find.text('Vincular con Nodo Sur'), findsOneWidget);
      expect(find.text('Vincular más tarde'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing, reason: 'es un paso del arranque, no una pantalla a la que volver');
    });

    testWidgets('con la cuenta ya vinculada el paso dice "Continuar"', (tester) async {
      await armar(conCuenta: true);
      await arrancar(tester);

      await tester.tap(find.byKey(const Key('modo-solo-celular')));
      await tester.pumpAndSettle();

      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Vincular más tarde'), findsNothing);
      // La sync de verdad arrancó (hay cuenta y no hay PC): se apaga acá para no dejar temporizadores al terminar.
      sync.servicio.detener();
    });

    testWidgets('tocar el modo que ya está en uso, desde Gestión, no cambia nada y vuelve', (tester) async {
      await armar(conCuenta: false);
      await guardarModoUso(ModoUso.soloCelular);
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PantallaElegirModo(
                  actual: ModoUso.soloCelular,
                  alElegir: (c, m) => elegirModo(c, m, actual: ModoUso.soloCelular),
                ),
              )),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Modo de uso'), findsOneWidget);

      await tester.tap(find.byKey(const Key('modo-solo-celular')));
      await tester.pumpAndSettle();
      expect(find.text('Modo de uso'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });
  });
}
