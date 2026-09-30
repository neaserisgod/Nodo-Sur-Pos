import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import '../helpers/base_para_tests.dart';

const _cuenta = CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-123', nombreDispositivo: 'Caja', vence: 99);

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(jsonEncode(cuerpo), estado);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // los tests abren una segunda base para leer la copia
  late AppDatabase db;
  late Directory tmp;
  late AlmacenCuentaEnMemoria almacen;

  setUp(() async {
    db = baseDeTest();
    tmp = await Directory.systemTemp.createTemp('nodosur_copias_');
    almacen = AlmacenCuentaEnMemoria();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  ServicioCopiasNube servicio(http.Client c, {DateTime Function()? reloj, DateTime? Function()? ultima, void Function(DateTime)? guardar}) =>
      ServicioCopiasNube(
        db: db,
        almacen: almacen,
        cliente: ClienteNube(http: c),
        carpetaTemporal: tmp,
        versionApp: () async => '1.0.0+2098',
        leerUltimaSubida: ultima == null ? null : () async => ultima(),
        guardarUltimaSubida: guardar == null ? null : (d) async => guardar(d),
        reloj: reloj ?? DateTime.now,
      );

  group('armar la copia', () {
    test('es la base entera, comprimida, con su hash, y conserva la versión del esquema', () async {
      final copia = await armarCopia(db, carpetaTemporal: tmp);
      expect(copia.sha256, sha256Hex(copia.bytes));
      final crudo = gzip.decode(copia.bytes);
      expect(String.fromCharCodes(crudo.sublist(0, 15)), 'SQLite format 3');
      expect(versionDeEsquemaDeArchivo(crudo), db.schemaVersion);
      // No deja archivos sueltos.
      expect(tmp.listSync(), isEmpty);
    });

    test('una copia trae los datos: abierta de nuevo tiene el usuario y las categorías', () async {
      final copia = await armarCopia(db, carpetaTemporal: tmp);
      final archivo = File('${tmp.path}/leida.sqlite')..writeAsBytesSync(gzip.decode(copia.bytes));
      final otra = AppDatabase(NativeDatabase(archivo));
      addTearDown(otra.close);
      expect((await otra.select(otra.categorias).get()).length, greaterThan(5));
      expect((await otra.select(otra.usuarios).get()).single.nombre, 'Dueño');
    });

    test('la versión de esquema de algo que no es SQLite es null', () {
      expect(versionDeEsquemaDeArchivo(List.filled(200, 7)), isNull);
      expect(versionDeEsquemaDeArchivo([1, 2, 3]), isNull);
    });
  });

  group('subir', () {
    test('sin cuenta vinculada no hace nada ni toca la red', () async {
      final s = servicio(MockClient((r) async => fail('no tenía que llamar')));
      expect(await s.subirAhora(), isA<SubidaSinCuenta>());
    });

    test('con cuenta: sube con hash, esquema y versión, y recuerda cuándo', () async {
      await almacen.guardar(_cuenta);
      late http.Request visto;
      DateTime? guardada;
      final s = servicio(MockClient((r) async {
        visto = r;
        return _json({'ok': true, 'id': 5, 'createdAt': 1, 'guardadas': 1});
      }), guardar: (d) => guardada = d);
      final r = await s.subirAhora();
      expect((r as SubidaOk).id, 5);
      expect(visto.headers['Authorization'], 'Bearer t1');
      expect(visto.headers['X-Schema-Version'], '${db.schemaVersion}');
      expect(visto.headers['X-App-Version'], '1.0.0+2098');
      expect(visto.headers['X-Sha256'], sha256Hex(visto.bodyBytes));
      expect(guardada, isNotNull);
    });

    test('suscripción vencida: queda como fallo con el motivo, sin tirar', () async {
      await almacen.guardar(_cuenta);
      final s = servicio(MockClient((r) async => _json({'error': 'no_upload'}, 403)));
      final r = await s.subirAhora() as SubidaFallida;
      expect(r.mensaje, contains('suscripción'));
      expect(r.pideVincular, isFalse);
    });

    test('cuenta desvinculada desde el sitio (401): pide volver a vincular', () async {
      await almacen.guardar(_cuenta);
      final s = servicio(MockClient((r) async => _json({'error': 'no_device'}, 401)));
      expect((await s.subirAhora() as SubidaFallida).pideVincular, isTrue);
    });

    test('sin internet: fallo entendible, y la copia se puede volver a intentar', () async {
      await almacen.guardar(_cuenta);
      var cae = true;
      final s = servicio(MockClient((r) async {
        if (cae) throw const SocketException('x');
        return _json({'ok': true, 'id': 1, 'createdAt': 1, 'guardadas': 1});
      }));
      expect(await s.subirAhora(), isA<SubidaFallida>());
      cae = false;
      expect(await s.subirAhora(), isA<SubidaOk>());
    });
  });

  group('copia diaria', () {
    test('sube si pasaron más de 24 h o nunca se subió; no sube si fue hace menos', () async {
      await almacen.guardar(_cuenta);
      var subidas = 0;
      var ahora = DateTime(2026, 9, 30, 12);
      DateTime? ultima;
      final s = servicio(
        MockClient((r) async {
          subidas++;
          return _json({'ok': true, 'id': subidas, 'createdAt': 1, 'guardadas': 1});
        }),
        reloj: () => ahora,
        ultima: () => ultima,
        guardar: (d) => ultima = d,
      );
      s.iniciarCopiaDiaria(cada: const Duration(milliseconds: 20));
      addTearDown(s.detener);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(subidas, 1); // la primera vez no había ninguna; después, hace menos de 24 h
      ahora = ahora.add(const Duration(hours: 25));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(subidas, 2);
    });
  });

  group('avisar', () {
    test('guarda el token renovado y devuelve el canal', () async {
      await almacen.guardar(_cuenta);
      final s = servicio(MockClient((r) async => _json({'ok': true, 'channel': 'beta', 'token': 'renovado'})));
      expect(await s.avisarYRenovar(cid: 'cid-12345678', sistema: 'Windows'), 'beta');
      expect((await almacen.leer())!.token, 'renovado');
    });

    test('si falla, no rompe y no toca la cuenta', () async {
      await almacen.guardar(_cuenta);
      final s = servicio(MockClient((r) async => throw const SocketException('x')));
      expect(await s.avisarYRenovar(cid: 'cid-12345678', sistema: 'Windows'), isNull);
      expect((await almacen.leer())!.token, 't1');
    });
  });

  group('restaurar', () {
    Future<(List<int>, String)> copiaDeEstaBase() async {
      final c = await armarCopia(db, carpetaTemporal: tmp);
      return (c.bytes, c.sha256);
    }

    test('baja, verifica el hash, descomprime y deja la base lista', () async {
      await almacen.guardar(_cuenta);
      final (bytes, sha) = await copiaDeEstaBase();
      final s = servicio(MockClient((r) async => http.Response.bytes(bytes, 200, headers: {'x-sha256': sha, 'x-schema-version': '${db.schemaVersion}'})));
      final lista = await s.prepararRestauracion(3);
      expect(File(lista.ruta).existsSync(), isTrue);
      expect(lista.schemaVersion, db.schemaVersion);
      final otra = AppDatabase(NativeDatabase(File(lista.ruta)));
      addTearDown(otra.close);
      expect((await otra.select(otra.usuarios).get()).single.nombre, 'Dueño');
    });

    test('si el hash no coincide, no deja nada', () async {
      await almacen.guardar(_cuenta);
      final (bytes, _) = await copiaDeEstaBase();
      final s = servicio(MockClient((r) async => http.Response.bytes(bytes, 200, headers: {'x-sha256': 'otro'})));
      await expectLater(s.prepararRestauracion(3), throwsA(isA<ErrorRestauracion>()));
      expect(tmp.listSync(), isEmpty);
    });

    test('una copia de una versión más nueva que la app se rechaza con un aviso claro', () async {
      await almacen.guardar(_cuenta);
      final (bytes, _) = await copiaDeEstaBase();
      final crudo = gzip.decode(bytes);
      crudo[63] = crudo[63] + 1; // user_version + 1
      final nueva = gzip.encode(crudo);
      final s = servicio(MockClient((r) async => http.Response.bytes(nueva, 200, headers: {'x-sha256': sha256Hex(nueva)})));
      await expectLater(
        s.prepararRestauracion(3),
        throwsA(isA<ErrorRestauracion>().having((e) => e.mensaje, 'mensaje', contains('más nueva'))),
      );
    });

    test('algo que no es una base SQLite se rechaza', () async {
      await almacen.guardar(_cuenta);
      final basura = gzip.encode(List.filled(300, 1));
      final s = servicio(MockClient((r) async => http.Response.bytes(basura, 200, headers: {'x-sha256': sha256Hex(basura)})));
      await expectLater(s.prepararRestauracion(3), throwsA(isA<ErrorRestauracion>()));
    });

    test('sin cuenta vinculada pide vincular primero', () async {
      final s = servicio(MockClient((r) async => fail('no tenía que llamar')));
      await expectLater(s.prepararRestauracion(3), throwsA(isA<ErrorRestauracion>()));
    });
  });
}
