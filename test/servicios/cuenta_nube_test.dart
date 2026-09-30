import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/domain/vinculacion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

http.Response _json(Object cuerpo, [int estado = 200]) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json'});

const _cuenta = CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-123', nombreDispositivo: 'Caja', vence: 99);

void main() {
  group('el almacén de la cuenta', () {
    test('en archivo: guarda, lee y borra; un archivo roto es "sin vincular"', () async {
      final carpeta = await Directory.systemTemp.createTemp('nodosur_cuenta_');
      addTearDown(() => carpeta.delete(recursive: true));
      final almacen = AlmacenCuentaEnArchivo(carpeta.path);
      expect(await almacen.leer(), isNull);

      await almacen.guardar(_cuenta);
      final leida = await almacen.leer();
      expect(leida!.token, 't1');
      expect(leida.email, 'a@b.com');
      expect(leida.nombreDispositivo, 'Caja');

      await File('${carpeta.path}/nodosur_cuenta.json').writeAsString('{roto');
      expect(await almacen.leer(), isNull);

      await almacen.guardar(_cuenta);
      await almacen.borrar();
      expect(await almacen.leer(), isNull);
      await almacen.borrar(); // borrar de nuevo no falla
    });
  });

  group('el cliente', () {
    test('estado: lee los permisos y las copias', () async {
      final c = ClienteNube(http: MockClient((r) async {
        expect(r.url.path, '/api/backups');
        expect(r.headers['Authorization'], 'Bearer t1');
        return _json({
          'upload': true,
          'restore': true,
          'max': 5,
          'backups': [
            {'id': 7, 'createdAt': 1700000000, 'size': 1234, 'sha256': 'ab', 'schemaVersion': 45, 'appVersion': '1.0.0', 'deviceName': 'Caja'},
          ],
        });
      }));
      final e = await c.estado('t1');
      expect(e.puedeSubir, isTrue);
      expect(e.puedeRestaurar, isTrue);
      expect(e.copias.single.id, 7);
      expect(e.copias.single.nombreDispositivo, 'Caja');
      expect(e.copias.single.creada, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('subir: manda los bytes con hash, esquema y versión, y devuelve el id', () async {
      late http.Request visto;
      final c = ClienteNube(http: MockClient((r) async {
        visto = r;
        return _json({'ok': true, 'id': 9, 'createdAt': 1, 'guardadas': 3});
      }));
      final r = await c.subir('t1', bytes: [1, 2, 3], sha256: 'abc', schemaVersion: 45, appVersion: '1.0.0+2098');
      expect(r.id, 9);
      expect(r.guardadas, 3);
      expect(visto.method, 'PUT');
      expect(visto.url.path, '/api/backup');
      expect(visto.headers['X-Sha256'], 'abc');
      expect(visto.headers['X-Schema-Version'], '45');
      expect(visto.headers['X-App-Version'], '1.0.0+2098');
      expect(visto.bodyBytes, [1, 2, 3]);
    });

    test('los errores del servidor salen con un texto claro y el código', () async {
      final c = ClienteNube(http: MockClient((r) async => _json({'error': 'no_upload'}, 403)));
      try {
        await c.subir('t1', bytes: [1], sha256: 'a', schemaVersion: 45, appVersion: '1');
        fail('tenía que fallar');
      } on ErrorNube catch (e) {
        expect(e.codigo, 'no_upload');
        expect(e.mensaje, contains('suscripción'));
        expect(e.pideVincularDeNuevo, isFalse);
      }
    });

    test('un 401 pide volver a vincular', () async {
      final c = ClienteNube(http: MockClient((r) async => _json({'error': 'no_device'}, 401)));
      try {
        await c.estado('t1');
        fail('tenía que fallar');
      } on ErrorNube catch (e) {
        expect(e.pideVincularDeNuevo, isTrue);
      }
    });

    test('sin conexión es un error entendible, no una excepción de socket', () async {
      final c = ClienteNube(http: MockClient((r) async => throw const SocketException('sin red')));
      try {
        await c.estado('t1');
        fail('tenía que fallar');
      } on ErrorNube catch (e) {
        expect(e.codigo, 'sin_red');
      }
    });

    test('bajar devuelve los bytes y el hash del servidor', () async {
      final c = ClienteNube(http: MockClient((r) async {
        expect(r.url.queryParameters['id'], '7');
        return http.Response.bytes([9, 8, 7], 200, headers: {'x-sha256': 'h', 'x-schema-version': '44'});
      }));
      final r = await c.bajar('t1', 7);
      expect(r.bytes, [9, 8, 7]);
      expect(r.sha256, 'h');
      expect(r.schemaVersion, 44);
    });

    test('avisar: informa el canal y el token renovado', () async {
      final c = ClienteNube(http: MockClient((r) async {
        final b = jsonDecode(r.body) as Map;
        expect(b['cid'], 'cid-1');
        expect(b['version'], '1.0.0');
        return _json({'ok': true, 'channel': 'beta', 'token': 'nuevo'});
      }));
      final r = await c.avisar('t1', cid: 'cid-1', version: '1.0.0', sistema: 'Windows');
      expect(r.canal, 'beta');
      expect(r.tokenNuevo, 'nuevo');
    });
  });

  group('vincular esta PC', () {
    test('abre el navegador, recibe el código en el servidor local, lo canjea y guarda la cuenta', () async {
      late Map canje;
      final cliente = ClienteNube(http: MockClient((r) async {
        expect(r.url.path, '/api/device/token');
        canje = jsonDecode(r.body) as Map;
        return _json({'token': 'tok', 'email': 'yo@gmail.com', 'deviceId': 'dev-123', 'expiresAt': 123});
      }));
      final almacen = AlmacenCuentaEnMemoria();
      Uri? abierta;

      final cuenta = await vincularEstaPc(
        cliente: cliente,
        almacen: almacen,
        idDispositivo: 'dev-123',
        nombre: 'Caja',
        abrirNavegador: (url) async {
          abierta = url;
          // Lo que haría el sitio: redirigir al servidor local con el código y el mismo state.
          final destino = Uri.parse('http://127.0.0.1:${url.queryParameters['port']}/callback?code=CODIGO&state=${url.queryParameters['state']}');
          final c = HttpClient();
          final resp = await (await c.getUrl(destino)).close();
          await resp.drain<void>();
          c.close();
        },
      );

      expect(cuenta.email, 'yo@gmail.com');
      expect((await almacen.leer())!.token, 'tok');
      expect(canje['code'], 'CODIGO');
      // El verificador que se canjea es el que generó el desafío que viajó en la dirección.
      expect(desafioDe(canje['verifier'] as String), abierta!.queryParameters['challenge']);
      expect(abierta!.host, 'horsepos.com');
      expect(abierta!.queryParameters['device'], 'dev-123');
    });

    test('un aviso con otro state no se acepta; si nunca llega el bueno, se cancela por tiempo', () async {
      final cliente = ClienteNube(http: MockClient((r) async => fail('no tenía que canjear nada')));
      final almacen = AlmacenCuentaEnMemoria();
      try {
        await vincularEstaPc(
          cliente: cliente,
          almacen: almacen,
          idDispositivo: 'dev-123',
          nombre: 'Caja',
          espera: const Duration(milliseconds: 300),
          abrirNavegador: (url) async {
            final destino = Uri.parse('http://127.0.0.1:${url.queryParameters['port']}/callback?code=X&state=OTRO');
            final c = HttpClient();
            final resp = await (await c.getUrl(destino)).close();
            expect(resp.statusCode, 400);
            await resp.drain<void>();
            c.close();
          },
        );
        fail('tenía que cancelarse');
      } on ErrorNube catch (e) {
        expect(e.codigo, 'vinculacion_cancelada');
      }
      expect(await almacen.leer(), isNull);
    });

    test('si el sitio rechaza el código, no se guarda nada', () async {
      final cliente = ClienteNube(http: MockClient((r) async => _json({'error': 'invalid_code'}, 400)));
      final almacen = AlmacenCuentaEnMemoria();
      try {
        await vincularEstaPc(
          cliente: cliente,
          almacen: almacen,
          idDispositivo: 'dev-123',
          nombre: 'Caja',
          abrirNavegador: (url) async {
            final destino = Uri.parse('http://127.0.0.1:${url.queryParameters['port']}/callback?code=X&state=${url.queryParameters['state']}');
            final c = HttpClient();
            await (await c.getUrl(destino)).close().then((r) => r.drain<void>());
            c.close();
          },
        );
        fail('tenía que fallar');
      } on ErrorNube catch (e) {
        expect(e.codigo, 'invalid_code');
      }
      expect(await almacen.leer(), isNull);
    });
  });
}
