import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/nube.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

const _cuenta = CuentaVinculada(token: 't1', email: 'yo@gmail.com', idDispositivo: 'dev-123', nombreDispositivo: 'Caja', vence: 1);

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(jsonEncode(cuerpo), estado);

Map<String, dynamic> _estado({bool sube = true, bool restaura = true, List<Map<String, dynamic>> copias = const []}) =>
    {'upload': sube, 'restore': restaura, 'max': 5, 'backups': copias};

const _copia = {'id': 7, 'createdAt': 1790000000, 'size': 2048, 'sha256': 'a', 'schemaVersion': 45, 'appVersion': '1.0', 'deviceName': 'Caja'};

/// Las acciones que arman o leen archivos de verdad (copias, restauración) corren en el reloj real: con el falso de
/// `testWidgets` el I/O de `dart:io` nunca se completa.
Future<void> _tocarConIO(WidgetTester tester, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late AlmacenCuentaEnMemoria almacen;

  setUp(() async {
    db = baseDeTest();
    tmp = await Directory.systemTemp.createTemp('nube_seccion_');
    almacen = AlmacenCuentaEnMemoria();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  NubeApp nubeCon(Future<http.Response> Function(http.Request) responde, {Future<void> Function(Uri)? abrir}) {
    final cliente = ClienteNube(http: MockClient(responde));
    return NubeApp(
      almacen: almacen,
      cliente: cliente,
      copias: ServicioCopiasNube(db: db, almacen: almacen, cliente: cliente, carpetaTemporal: tmp, versionApp: () async => '1.0.0'),
      idDispositivo: () async => 'dev-123',
      nombreDispositivo: () => 'Caja',
      abrirNavegador: abrir ?? (_) async {},
      carpetaTemporal: tmp,
    );
  }

  Future<void> abrirSeccion(WidgetTester tester, NubeApp? nube) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaConfiguracion(db: db, usuarioId: 1, nube: nube)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta de Nodo Sur'));
    await tester.pumpAndSettle();
  }

  testWidgets('sin vincular: explica y ofrece vincular', (tester) async {
    await abrirSeccion(tester, nubeCon((r) async => fail('no tenía que llamar a nada')));
    expect(find.text('Vincular con mi cuenta'), findsOneWidget);
    expect(find.byKey(const Key('nube_vinculada')), findsNothing);
  });

  testWidgets('sin la cuenta armada (instalación sin red ni servicio) avisa que no está disponible', (tester) async {
    await abrirSeccion(tester, null);
    expect(find.byKey(const Key('nube_no_disponible')), findsOneWidget);
  });

  testWidgets('vinculada: muestra el correo, las copias y deja restaurar', (tester) async {
    await almacen.guardar(_cuenta);
    await abrirSeccion(tester, nubeCon((r) async => _json(_estado(copias: [_copia]))));
    expect(find.textContaining('yo@gmail.com'), findsOneWidget);
    expect(find.byKey(const Key('nube_copia_7')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const Key('nube_copia_7')), matching: find.byType(OutlinedButton))).onPressed, isNotNull);
  });

  testWidgets('con una caja abierta no se puede restaurar y se explica por qué', (tester) async {
    await almacen.guardar(_cuenta);
    final u = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: u, fondoInicialCentavos: 0);
    await abrirSeccion(tester, nubeCon((r) async => _json(_estado(copias: [_copia]))));
    expect(tester.widget<OutlinedButton>(find.descendant(of: find.byKey(const Key('nube_copia_7')), matching: find.byType(OutlinedButton))).onPressed, isNull);
    expect(find.textContaining('caja abierta'), findsOneWidget);
  });

  testWidgets('sin suscripción activa: no se puede guardar pero sí restaurar, y se dice', (tester) async {
    await almacen.guardar(_cuenta);
    await abrirSeccion(tester, nubeCon((r) async => _json(_estado(sube: false, copias: [_copia]))));
    expect(find.byKey(const Key('nube_sin_permiso_subir')), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Guardar una copia ahora')).onPressed, isNull);
  });

  testWidgets('"Guardar una copia ahora" sube y avisa', (tester) async {
    await almacen.guardar(_cuenta);
    final pedidos = <String>[];
    await abrirSeccion(tester, nubeCon((r) async {
      pedidos.add('${r.method} ${r.url.path}');
      if (r.method == 'PUT') return _json({'ok': true, 'id': 8, 'createdAt': 1, 'guardadas': 1});
      return _json(_estado());
    }));
    await _tocarConIO(tester, find.text('Guardar una copia ahora'));
    expect(pedidos, contains('PUT /api/backup'));
    expect(find.byKey(const Key('nube_aviso')), findsOneWidget);
  });

  testWidgets('si el servidor rechaza la copia, se muestra el motivo', (tester) async {
    await almacen.guardar(_cuenta);
    await abrirSeccion(tester, nubeCon((r) async {
      if (r.method == 'PUT') return _json({'error': 'hash_mismatch'}, 422);
      return _json(_estado());
    }));
    await _tocarConIO(tester, find.text('Guardar una copia ahora'));
    expect(find.byKey(const Key('nube_error')), findsOneWidget);
    expect(find.textContaining('dañó'), findsOneWidget);
  });

  testWidgets('desvincular saca la cuenta de la PC (las copias quedan en la nube)', (tester) async {
    await almacen.guardar(_cuenta);
    await abrirSeccion(tester, nubeCon((r) async => _json(_estado())));
    await tester.tap(find.text('Desvincular esta PC'));
    await tester.pumpAndSettle();
    expect(await almacen.leer(), isNull);
    expect(find.text('Vincular con mi cuenta'), findsOneWidget);
  });

  testWidgets('restaurar una copia dañada muestra el error y no pide confirmación', (tester) async {
    await almacen.guardar(_cuenta);
    await abrirSeccion(tester, nubeCon((r) async {
      if (r.url.path == '/api/backup') return http.Response.bytes([1, 2, 3], 200, headers: {'x-sha256': 'otro'});
      return _json(_estado(copias: [_copia]));
    }));
    await _tocarConIO(tester, find.descendant(of: find.byKey(const Key('nube_copia_7')), matching: find.text('Restaurar')));
    expect(find.byKey(const Key('nube_error_restaurar')), findsOneWidget);
    expect(find.text('¿Restaurar este respaldo?'), findsNothing);
  });

  testWidgets('restaurar una copia buena pide la confirmación fuerte antes de tocar nada', (tester) async {
    await almacen.guardar(_cuenta);
    final buena = (await tester.runAsync(() => armarCopia(db, carpetaTemporal: tmp)))!;
    await abrirSeccion(tester, nubeCon((r) async {
      if (r.url.path == '/api/backup') {
        return http.Response.bytes(buena.bytes, 200, headers: {'x-sha256': buena.sha256});
      }
      return _json(_estado(copias: [_copia]));
    }));
    await _tocarConIO(tester, find.descendant(of: find.byKey(const Key('nube_copia_7')), matching: find.text('Restaurar')));
    expect(find.text('¿Restaurar este respaldo?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    // Cancelar no toca la base: sigue abierta y con sus datos.
    expect((await db.select(db.usuarios).get()).length, greaterThanOrEqualTo(1));
  });
}
