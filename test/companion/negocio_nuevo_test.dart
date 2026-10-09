// "Configurá tu negocio" (`configurar/`): cuándo un negocio es nuevo, qué se crea para dejarlo listo para vender, los
// pasos pendientes de Inicio, el asistente y la decisión al entrar con la cuenta.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/configurar/asistente_negocio.dart';
import 'package:la_plazoleta/companion/configurar/negocio_nuevo.dart';
import 'package:la_plazoleta/companion/configurar/pendientes_en_inicio.dart';
import 'package:la_plazoleta/companion/pantalla_entrar_con_cuenta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/servidor_sync_falso.dart';

/// Una base como la del celular recién instalado: sin reglas del negocio ni categorías. (Los tests corren fuera de
/// Android, así que la base siembra lo del escritorio; se borra lo que el celular no tendría.)
Future<AppDatabase> _baseDeCelularNuevo() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.delete(db.configuracionNegocioTabla).go();
  await db.delete(db.categorias).go();
  return db;
}

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('¿el negocio es nuevo?', () {
    test('un celular recién instalado no tiene nada del negocio', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      expect(await baseSinNegocio(db), isTrue, reason: '"Varios" no cuenta como un producto del comercio');
    });

    test('con las reglas, una categoría o un producto ya no es nuevo', () async {
      for (final cargar in <Future<void> Function(AppDatabase)>[
        prepararNegocioNuevo,
        (db) => db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: 'Bebidas')),
        (db) => db.into(db.productos).insert(const ProductosCompanion(nombre: Value('Yerba'))),
      ]) {
        final db = await _baseDeCelularNuevo();
        await cargar(db);
        expect(await baseSinNegocio(db), isFalse);
        await db.close();
      }
    });
  });

  group('dejar la base lista para vender', () {
    test('crea las reglas del negocio con recargo en \$0 y redondeo de \$100, listas para sincronizar', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      await prepararNegocioNuevo(db);
      final c = await db.select(db.configuracionNegocioTabla).getSingle();
      expect([c.recargoPrimerAtadoCentavos, c.recargoAtadoAdicionalCentavos, c.recargoSueltoCentavos], [0, 0, 0]);
      expect(c.pasoRedondeoCentavos, 10000);
      expect(c.modulosDesactivados, Modulo.compararPrecios.clave, reason: 'como en la PC, el comparador arranca apagado');
      expect(c.globalId, isNotNull, reason: 'sin global_id no sube a la nube');
      expect(c.actualizadoEn, isNotNull);
    });

    test('es idempotente: no crea una segunda fila de reglas', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      await prepararNegocioNuevo(db);
      await prepararNegocioNuevo(db);
      expect(await db.select(db.configuracionNegocioTabla).get(), hasLength(1));
    });

    test('nombre y rubro: guarda el nombre y crea las categorías de la plantilla, sin repetir', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      await db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: 'bebidas'));
      await guardarNegocio(db, nombre: '  Almacén Don Pepe ', rubro: PlantillaRubro.almacen);
      await guardarNegocio(db, nombre: 'Almacén Don Pepe', rubro: PlantillaRubro.almacen);

      final config = await db.select(db.configuracionNegocioTabla).getSingle();
      expect(config.nombreComercio, 'Almacén Don Pepe');
      expect(config.rubro, 'almacen', reason: 'desde la v63 el rubro queda guardado (lo usa el bot de WhatsApp)');
      final categorias = await db.select(db.categorias).get();
      expect(categorias, hasLength(PlantillaRubro.almacen.categorias.length), reason: '"bebidas" ya estaba y no se repite');
      final nuevas = categorias.where((c) => c.nombre != 'bebidas');
      expect(nuevas.every((c) => c.globalId != null && c.actualizadoEn != null), isTrue);
    });

    test('una barbería: guarda el rubro, siembra sus categorías y la app pasa a ser de servicios', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      await guardarNegocio(db, nombre: 'Barbería del Centro', rubro: PlantillaRubro.barberia);

      expect((await db.select(db.configuracionNegocioTabla).getSingle()).rubro, 'barberia');
      expect((await db.select(db.categorias).get()).map((c) => c.nombre).toSet(), {'Cortes', 'Barba', 'Color'});
      final modulos = await modulosNegocioActuales(db);
      expect(modulos.forma, FormaDeTrabajo.servicios);
      expect(modulos.estaActivo(Modulo.cajaAparte), isFalse, reason: 'la lata de cigarrillos es de un comercio');
      expect(modulos.estaActivo(Modulo.fiado), isTrue);
    });

    test('el rubro "Otro" no trae categorías', () async {
      final db = await _baseDeCelularNuevo();
      addTearDown(db.close);
      await guardarNegocio(db, nombre: 'Lo de Ana', rubro: PlantillaRubro.otro);
      expect(await db.select(db.categorias).get(), isEmpty);
    });
  });

  group('decidir después de bajar todo de la nube', () {
    Future<(SyncNubeCompanion, AppDatabase)> armar({required bool conCuenta, bool caido = false}) async {
      final almacen = AlmacenCuentaEnMemoria();
      if (conCuenta) {
        await almacen.guardar(const CuentaVinculada(token: 'tok', email: 'a@b.com', idDispositivo: 'd', nombreDispositivo: 'Celular', vence: 99));
      }
      final servidor = ServidorSyncFalso()..caido = caido;
      final db = await _baseDeCelularNuevo();
      final sync = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
        abrirNavegador: (_) async {},
        db: db,
      );
      addTearDown(() async {
        sync.servicio.detener();
        sync.conmutador.cerrar();
        await db.close();
      });
      return (sync, db);
    }

    test('con la nube vacía y la base vacía, es nuevo', () async {
      final (sync, db) = await armar(conCuenta: true);
      expect(await esNegocioNuevoTrasSincronizar(sync: sync.servicio, db: db), isTrue);
    });

    test('sin poder sincronizar no se decide que es nuevo: ante la duda no se crea nada', () async {
      final (sinCuenta, db1) = await armar(conCuenta: false);
      expect(await esNegocioNuevoTrasSincronizar(sync: sinCuenta.servicio, db: db1), isFalse);
      final (caido, db2) = await armar(conCuenta: true, caido: true);
      expect(await esNegocioNuevoTrasSincronizar(sync: caido.servicio, db: db2), isFalse);
    });

    test('si ya hay datos del negocio, no es nuevo', () async {
      final (sync, db) = await armar(conCuenta: true);
      await db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: 'Bebidas'));
      expect(await esNegocioNuevoTrasSincronizar(sync: sync.servicio, db: db), isFalse);
    });
  });

  group('pasos pendientes', () {
    test('se guardan, se leen y se van marcando; sin pendientes no queda nada guardado', () async {
      expect(await leerPasosPendientes(), isEmpty);
      await guardarPasosPendientes(PasoNegocio.values.toSet());
      expect(await leerPasosPendientes(), PasoNegocio.values.toSet());
      await marcarPasoHecho(PasoNegocio.negocio);
      expect(pasosPendientesNegocio.value, {PasoNegocio.producto, PasoNegocio.cobros});
      await marcarPasoHecho(PasoNegocio.producto);
      await marcarPasoHecho(PasoNegocio.cobros);
      expect(await leerPasosPendientes(), isEmpty);
      expect((await SharedPreferences.getInstance()).getStringList('companion_configuracion_pendiente'), isNull);
    });
  });

  group('el asistente', () {
    setUpAll(_cargarFigtree);

    Widget app(Widget home) => MaterialApp(
          theme: TemaCompanion.claro,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: home,
        );

    Future<void> tamanio(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
    }

    testWidgets('de punta a punta: guarda el negocio, el producto de práctica y avisa cada paso hecho', (t) async {
      await tamanio(t);
      final hechos = <PasoNegocio>[];
      (String, PlantillaRubro)? negocio;
      ProductoDePrueba? producto;
      Set<PasoNegocio>? alFinal;
      await t.pumpWidget(app(AsistenteNegocio(
        alGuardarNegocio: (n, r) async => negocio = (n, r),
        alEscanear: (_) async => '7790387013150',
        alGuardarProducto: (p) async => producto = p,
        alAbrirWeb: (_) {},
        alCompletarPaso: hechos.add,
        alTerminar: (_, p) => alFinal = p,
      )));
      await t.pumpAndSettle();

      final siguiente = find.byKey(const Key('asistente-seguir'));
      expect(t.widget<BotonNs>(find.descendant(of: siguiente, matching: find.byType(BotonNs))).habilitado, isFalse, reason: 'sin nombre ni rubro no se sigue');
      await t.enterText(find.byKey(const Key('asistente-nombre')), 'Almacén Don Pepe');
      await t.tap(find.byKey(const Key('rubro-kiosco')));
      await t.pump();
      expect(find.textContaining('categorías para empezar: Golosinas'), findsOneWidget, reason: 'muestra las categorías del rubro elegido');
      await t.tap(siguiente);
      await t.pumpAndSettle();
      expect(negocio, ('Almacén Don Pepe', PlantillaRubro.kiosco));

      await t.tap(find.byKey(const Key('asistente-escanear')));
      await t.pumpAndSettle();
      expect(find.text('7790387013150'), findsOneWidget);
      await t.enterText(find.byKey(const Key('producto-nombre')), 'Alfajor triple');
      await t.enterText(find.byKey(const Key('producto-precio')), '1200');
      await t.tap(find.text('Golosinas'));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('producto-guardar')));
      await t.tap(find.byKey(const Key('producto-guardar')));
      await t.pumpAndSettle();
      expect(producto?.precioCentavos, 120000, reason: 'la plata siempre en centavos');
      expect(producto?.categoria, 'Golosinas');
      expect(find.text('¡Ya lo podés vender!'), findsOneWidget);
      await t.tap(find.byKey(const Key('asistente-seguir')));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('asistente-terminar')));
      expect(hechos, PasoNegocio.values);
      expect(alFinal, isEmpty);
    });

    testWidgets('los rubros van en dos grupos y uno de servicios avisa que la agenda llega después', (t) async {
      await tamanio(t);
      (String, PlantillaRubro)? negocio;
      await t.pumpWidget(app(AsistenteNegocio(
        alGuardarNegocio: (n, r) async => negocio = (n, r),
        alEscanear: (_) async => null,
        alGuardarProducto: (_) async {},
        alAbrirWeb: (_) {},
        alCompletarPaso: (_) {},
        alTerminar: (_, _) {},
      )));
      await t.pumpAndSettle();

      final grupos = find.byWidgetPredicate((w) => w is SeccionNs, skipOffstage: false).evaluate().map((e) => (e.widget as SeccionNs).texto);
      expect(grupos, containsAllInOrder(['Vendés productos', 'Das servicios', '¿Ninguno?']));
      await t.enterText(find.byKey(const Key('asistente-nombre')), 'Estudio Lila');
      await t.dragUntilVisible(find.byKey(const Key('rubro-otro')), find.byType(ListView), const Offset(0, -200));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rubro-unas')));
      await t.pump();
      expect(find.textContaining('Manos, Pies, Cejas y pestañas', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('La agenda y los servicios', skipOffstage: false), findsOneWidget, reason: 'no se promete lo que todavía no está');
      await t.tap(find.byKey(const Key('asistente-seguir')));
      await t.pumpAndSettle();
      expect(negocio, ('Estudio Lila', PlantillaRubro.unas));
    });

    testWidgets('"Después" deja el paso pendiente y no lo da por hecho', (t) async {
      await tamanio(t);
      final hechos = <PasoNegocio>[];
      Set<PasoNegocio>? alFinal;
      await t.pumpWidget(app(AsistenteNegocio(
        alGuardarNegocio: (_, _) async {},
        alEscanear: (_) async => null,
        alGuardarProducto: (_) async {},
        alAbrirWeb: (_) {},
        alCompletarPaso: hechos.add,
        alTerminar: (_, p) => alFinal = p,
      )));
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const Key('asistente-despues')));
        await t.pumpAndSettle();
      }
      expect(hechos, isEmpty);
      expect(alFinal, PasoNegocio.values.toSet());
    });

    testWidgets('retomado en el producto sin rubro elegido, ofrece las categorías que ya tiene la base', (t) async {
      await tamanio(t);
      await t.pumpWidget(app(AsistenteNegocio(
        pasoInicial: PasoNegocio.producto,
        categoriasExistentes: const ['Fiambres', 'Quesos'],
        alGuardarNegocio: (_, _) async {},
        alEscanear: (_) async => '123',
        alGuardarProducto: (_) async {},
        alAbrirWeb: (_) {},
        alTerminar: (_, _) {},
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('asistente-escanear')));
      await t.pumpAndSettle();
      expect(find.text('Quesos'), findsOneWidget);
    });

    testWidgets('si se cancela la cámara se queda en la invitación a escanear', (t) async {
      await tamanio(t);
      await t.pumpWidget(app(AsistenteNegocio(
        pasoInicial: PasoNegocio.producto,
        alGuardarNegocio: (_, _) async {},
        alEscanear: (_) async => null,
        alGuardarProducto: (_) async => fail('no hay producto que guardar'),
        alAbrirWeb: (_) {},
        alTerminar: (_, _) {},
      )));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('asistente-escanear')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('asistente-escanear')), findsOneWidget);
    });
  });

  group('la tarjeta de Inicio', () {
    setUpAll(_cargarFigtree);

    Future<void> abrir(WidgetTester t) async {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: const Scaffold(body: PendientesEnInicio())));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
    }

    testWidgets('sin pasos pendientes no ocupa lugar', (t) async {
      await t.runAsync(() => guardarPasosPendientes({}));
      await abrir(t);
      expect(find.byKey(const Key('inicio-pendientes')), findsNothing);
    });

    testWidgets('con pasos pendientes dice cuántos y cuáles', (t) async {
      await t.runAsync(() => guardarPasosPendientes({PasoNegocio.producto, PasoNegocio.cobros}));
      await abrir(t);
      expect(find.byKey(const Key('inicio-pendientes')), findsOneWidget);
      expect(find.text('Te faltan 2 pasos'), findsOneWidget);
      expect(find.text('Tu primer producto · Mercado Pago y equipo'), findsOneWidget);
    });
  });

  group('al entrar con la cuenta', () {
    setUpAll(_cargarFigtree);

    Future<void> entrar(WidgetTester t, {required bool nuevo}) async {
      final db = (await t.runAsync(() async => _baseDeCelularNuevo()))!;
      usarBaseLocalDeTest(db);
      final almacen = AlmacenCuentaEnMemoria();
      await almacen.guardar(const CuentaVinculada(token: 'tok', email: 'pepe@x.com', idDispositivo: 'd', nombreDispositivo: 'Celular', vence: 99));
      final sync = armarSyncNubeCompanion(
        almacen: almacen,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(
          http: MockClient((r) async => http.Response('{"email":"pepe@x.com","name":"Pepe","role":"owner","orgId":1,"branchId":1}', 200,
              headers: {'content-type': 'application/json'})),
        ),
        abrirNavegador: (_) async {},
        db: db,
      );
      addTearDown(() async {
        sync.servicio.detener();
        sync.conmutador.cerrar();
        await t.runAsync(db.close);
      });
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: TemaCompanion.claro,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: PantallaEntrarConCuenta(sync: sync, servicio: () async => PuertoLocal(db), esNegocioNuevo: (perfil) async {
          expect(perfil.rol, rolDuenio);
          return nuevo;
        }),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      }
      await t.pumpAndSettle();
    }

    testWidgets('el dueño de un negocio nuevo sigue a "Configurar mi negocio"', (t) async {
      await entrar(t, nuevo: true);
      expect(find.text('Listo, Pepe.'), findsOneWidget);
      expect(find.text('Configurar mi negocio'), findsOneWidget);
      await t.tap(find.text('Configurar mi negocio'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await t.pumpAndSettle();
      expect(find.text('Contanos de tu negocio'), findsOneWidget);
    });

    testWidgets('si no es un negocio nuevo, de "Listo" va directo al inicio', (t) async {
      await entrar(t, nuevo: false);
      expect(find.text('Listo, Pepe.'), findsOneWidget);
      expect(find.text('Ir al inicio'), findsOneWidget);
    });
  });
}
