import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/conmutador_sync.dart';
import 'package:la_plazoleta/companion/pantalla_cuenta_companion.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/servidor_sync_falso.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<SyncNubeCompanion> armar({bool vinculada = false}) async {
    final almacen = AlmacenCuentaEnMemoria();
    if (vinculada) {
      await almacen.guardar(const CuentaVinculada(
        token: 'tok-cel', email: 'ana@x.com', idDispositivo: 'android-1', nombreDispositivo: 'Celular (android)', vence: 99));
    }
    final servidor = ServidorSyncFalso();
    final db = baseDeTest();
    addTearDown(db.close);
    final sync = armarSyncNubeCompanion(
      almacen: almacen,
      almacenEstado: AlmacenEstadoSyncEnMemoria(),
      cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
      abrirNavegador: (_) async {},
      db: db,
    );
    addTearDown(() {
      sync.servicio.detener();
      sync.conmutador.cerrar();
    });
    return sync;
  }

  Future<void> abrir(WidgetTester tester, SyncNubeCompanion sync) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: PantallaCuentaCompanion(sync: sync),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sin cuenta: dice que está solo en el celular y ofrece vincular', (tester) async {
    final sync = await armar();
    await abrir(tester, sync);
    expect(find.text('Solo en este celular'), findsOneWidget);
    expect(find.text('Sin vincular'), findsOneWidget);
    expect(find.text('Vincular con Nodo Sur'), findsOneWidget);
    expect(find.text('Desvincular'), findsNothing);
  });

  testWidgets('con cuenta: muestra el mail y deja sincronizar ahora o desvincular', (tester) async {
    final sync = await armar(vinculada: true);
    await abrir(tester, sync);
    expect(find.text('ana@x.com'), findsOneWidget);
    expect(find.text('Sincronizar ahora'), findsOneWidget);
    expect(find.text('Desvincular'), findsOneWidget);
  });

  testWidgets('el cartel sigue al modo: PC conectada → "Con la PC"; PC caída y con cuenta → "Por internet"', (tester) async {
    final sync = await armar(vinculada: true);
    sync.conmutador.definirPc(emparejada: true);
    sync.conmutador.pcConectada(true);
    await abrir(tester, sync);
    expect(find.text('Con la PC'), findsOneWidget);

    sync.conmutador.modo.value = ModoSync.nube;
    await tester.pumpAndSettle();
    expect(find.text('Por internet'), findsOneWidget);
  });

  testWidgets('desvincular pide confirmación y deja la cuenta sin vincular', (tester) async {
    final sync = await armar(vinculada: true);
    await abrir(tester, sync);
    await tester.tap(find.text('Desvincular'));
    await tester.pumpAndSettle();
    expect(find.text('¿Desvincular este celular?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Desvincular').last);
    await tester.pumpAndSettle();
    expect(await sync.cuenta(), isNull);
    expect(find.text('Vincular con Nodo Sur'), findsOneWidget);
  });

  test('textoDeResultado: cada resultado tiene un texto claro', () {
    expect(textoDeResultado(const SyncNubeOk(bajadas: 0, subidas: 0)), 'Todo al día.');
    expect(textoDeResultado(const SyncNubeOk(bajadas: 2, subidas: 1)), contains('2'));
    expect(textoDeResultado(const SyncNubeSinCuenta()), contains('vinculá'));
    expect(textoDeResultado(const SyncNubeFallida('x', sinRed: true)), 'Sin conexión a internet.');
    expect(textoDeResultado(const SyncNubeExpirada()), contains('copia'));
  });
}
