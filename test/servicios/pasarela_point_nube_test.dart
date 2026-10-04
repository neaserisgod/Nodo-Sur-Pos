// Cobrar con la terminal por el servidor (2026-10-02): la PC de siempre sigue cobrando directo; lo nuevo es para quien no tiene el
// access token (el celular sin PC, una PC sin token cargado) y solo anda si el negocio conectó Mercado Pago y eligió terminal.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/cobro_posnet.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/pasarela_point_nube.dart';

http.Response _json(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

Future<AlmacenCuentaEnMemoria> _conCuenta() async {
  final a = AlmacenCuentaEnMemoria();
  await a.guardar(const CuentaVinculada(token: 'tok-dispositivo', email: 'a@b.com', idDispositivo: 'd', nombreDispositivo: 'Cel', vence: 99));
  return a;
}

ClienteNube _cliente(Future<http.Response> Function(http.Request) f) => ClienteNube(http: MockClient(f));

Map<String, dynamic> _estado({bool conectado = true, bool reconectar = false, bool terminal = true}) =>
    {'connected': conectado, 'needsReconnect': reconectar, 'terminalConfigured': terminal};

void main() {
  group('elegirPasarelaPoint', () {
    test('con access token y terminal cargados en el equipo cobra directo, sin preguntarle nada al servidor', () async {
      final p = await elegirPasarelaPoint(
        accessToken: 'APP_USR-x', terminalId: 'T1', almacen: await _conCuenta(), cliente: _cliente((r) async => fail('no tenía que llamar al servidor')));
      expect(p, isA<PasarelaPointDirecta>());
    });

    test('sin token y con la cuenta vinculada, el negocio conectado y la terminal elegida, cobra por el servidor', () async {
      final p = await elegirPasarelaPoint(
        almacen: await _conCuenta(),
        cliente: _cliente((r) async {
          expect(r.url.path, '/api/mp/estado');
          expect(r.headers['Authorization'], 'Bearer tok-dispositivo');
          return _json(_estado());
        }),
      );
      expect(p, isA<PasarelaPointNube>());
    });

    test('cada cosa que falta se dice con su arreglo, sin tocar la terminal', () async {
      Future<String> mensaje(Map<String, dynamic>? estado, {bool cuenta = true, int status = 200}) async {
        try {
          await elegirPasarelaPoint(
            almacen: cuenta ? await _conCuenta() : AlmacenCuentaEnMemoria(),
            cliente: _cliente((r) async => estado == null ? _json({'error': 'no_device'}, status) : _json(estado)),
          );
        } on CobroPosnetException catch (e) {
          return e.mensaje;
        }
        fail('tenía que fallar');
      }

      expect(await mensaje(null, cuenta: false), contains('Configurá el access token y la terminal de cobro'));
      expect(await mensaje(_estado(conectado: false)), contains('todavía no está conectado'));
      expect(await mensaje(_estado(conectado: false, reconectar: true)), contains('se cortó'));
      expect(await mensaje(_estado(terminal: false)), contains('no tiene una terminal elegida'));
      expect(await mensaje(null, status: 401), contains('ya no está vinculado'));
    });

    test('con el token cargado solo a medias (falta la terminal) NO cobra directo: cae a la cuenta', () async {
      final p = await elegirPasarelaPoint(accessToken: 'APP_USR-x', almacen: await _conCuenta(), cliente: _cliente((r) async => _json(_estado())));
      expect(p, isA<PasarelaPointNube>());
    });
  });

  group('PasarelaPointNube', () {
    test('crear: manda el pedido al servidor con la clave de idempotencia y devuelve el id y el estado', () async {
      late Map<String, dynamic> cuerpo;
      final p = PasarelaPointNube(
        token: 'tok-dispositivo',
        cliente: _cliente((r) async {
          expect(r.url.path, '/api/mp/orden');
          expect(r.headers['Authorization'], 'Bearer tok-dispositivo');
          cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'id': 'ORD1', 'status': 'created', 'statusDetail': null});
        }),
      );
      final o = await p.crear(externalReference: 'venta-1', idempotencyKey: 'clave-0001-abc', montoCentavos: 123450, canal: 'qr');
      expect((o.ordenIdMp, o.estado), ('ORD1', 'created'));
      expect(cuerpo, {'externalReference': 'venta-1', 'idempotencyKey': 'clave-0001-abc', 'montoCentavos': 123450, 'canal': 'qr'});
    });

    test('un rechazo de Mercado Pago llega con su código y su motivo, no como un error mudo', () async {
      final p = PasarelaPointNube(
        token: 't',
        cliente: _cliente((r) async => _json({'error': 'mp_rechazo', 'status': 403, 'mensaje': 'forbidden_checking_terminal_owner · Terminal no vinculada'}, 502)),
      );
      await expectLater(
        p.crear(externalReference: 'v', idempotencyKey: 'clave-0001-abc', montoCentavos: 100, canal: 'qr'),
        throwsA(isA<CobroPosnetException>().having((e) => e.mensaje, 'mensaje', allOf(contains('forbidden_checking_terminal_owner'), contains('Mercado Pago respondió')))),
      );
    });

    test('consultar devuelve el estado; sin red se dice sin red', () async {
      final ok = PasarelaPointNube(token: 't', cliente: _cliente((r) async {
        expect(r.url.queryParameters['id'], 'ORD1');
        return _json({'id': 'ORD1', 'status': 'processed'});
      }));
      expect(await ok.consultar('ORD1'), 'processed');
    });

    test('cancelar una orden que ya llegó a la terminal da el mensaje de negocio de siempre', () async {
      final p = PasarelaPointNube(
        token: 't',
        cliente: _cliente((r) async => _json({'error': 'mp_rechazo', 'status': 409, 'mensaje': 'cannot_cancel_order · no se puede'}, 502)),
      );
      await expectLater(p.cancelar('ORD1'), throwsA(isA<CobroPosnetException>().having((e) => e.mensaje, 'mensaje', contains('ya recibió la orden'))));
    });

    test('crear: un rechazo (mp_rechazo, 4xx de Mercado Pago) es definitivo; sin red o sin respuesta (504/5xx) es incierto', () async {
      Future<CobroPosnetException> falla(Future<http.Response> Function(http.Request) f) async {
        final p = PasarelaPointNube(token: 't', cliente: _cliente(f));
        try {
          await p.crear(externalReference: 'v', idempotencyKey: 'clave-0001-abc', montoCentavos: 100, canal: 'qr');
        } on CobroPosnetException catch (e) {
          return e;
        }
        fail('tenía que fallar');
      }

      expect((await falla((r) async => _json({'error': 'mp_rechazo', 'status': 400, 'mensaje': 'terminal inválida'}, 502))).incierto, isFalse);
      expect((await falla((r) async => _json({'error': 'mp_no_conectado'}, 409))).incierto, isFalse);
      expect((await falla((r) async => _json({'error': 'mp_sin_respuesta', 'status': 503, 'mensaje': 'no respondió'}, 504))).incierto, isTrue);
      expect((await falla((r) async => _json({'error': 'mp_error'}, 502))).incierto, isTrue, reason: 'Mercado Pago sin cuerpo: no se sabe');
      expect((await falla((r) async => http.Response('<html>Bad gateway</html>', 502))).incierto, isTrue);
      expect((await falla((r) async => throw const SocketException('sin internet'))).incierto, isTrue);
    });

    test('un dispositivo ya no vinculado (401) pide volver a vincularlo', () async {
      final p = PasarelaPointNube(token: 't', cliente: _cliente((r) async => _json({'error': 'no_device'}, 401)));
      await expectLater(p.consultar('ORD1'), throwsA(isA<CobroPosnetException>().having((e) => e.mensaje, 'mensaje', contains('ya no está vinculado'))));
    });
  });
}
