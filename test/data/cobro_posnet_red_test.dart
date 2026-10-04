// Revisión de blindaje (2026-10-04): el cobro con la Point cuando falla internet.
//
// Antes, con el access token cargado en la PC, un corte de red durante el cobro tiraba una `SocketException` que ningún diálogo
// entendía (solo atrapan `CobroPosnetException`): el cobro quedaba girando para siempre, sin mensaje, con la orden quizá creada
// del lado de Mercado Pago. Ahora todo corte se vuelve `CobroPosnetException(incierto)` y el reintento reutiliza la MISMA orden.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/cobro_posnet.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';

import '../helpers/base_para_tests.dart';

Future<OrdenCobroCreada> _crear(http.Client client) => crearOrdenCobro(
      accessToken: 't',
      terminalId: 'term',
      externalReference: 'ref',
      idempotencyKey: 'clave',
      montoCentavos: 100000,
      canal: 'qr',
      client: client,
    );

class _PasarelaFalsa implements PasarelaPoint {
  _PasarelaFalsa(this.respuestas);
  final List<Object> respuestas; // OrdenCobroCreada o una excepción
  final claves = <String>[];
  final referencias = <String>[];

  @override
  Future<OrdenCobroCreada> crear({
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  }) async {
    claves.add(idempotencyKey);
    referencias.add(externalReference);
    final r = respuestas.removeAt(0);
    if (r is OrdenCobroCreada) return r;
    throw r;
  }

  @override
  Future<String> consultar(String ordenIdMp) async => 'created';

  @override
  Future<void> cancelar(String ordenIdMp) async {}
}

void main() {
  group('cobro directo con Mercado Pago: la red se cae', () {
    test('sin conexión (SocketException): CobroPosnetException incierto, con un mensaje que se puede mostrar', () async {
      final client = MockClient((_) async => throw const SocketException('Network is unreachable'));
      await expectLater(
        _crear(client),
        throwsA(isA<CobroPosnetException>().having((e) => e.incierto, 'incierto', true).having((e) => e.mensaje, 'mensaje', contains('conexión'))),
      );
    });

    test('un error de cliente HTTP (ClientException) y uno de TLS también', () async {
      for (final error in <Object>[http.ClientException('Connection closed before full header was received'), const HandshakeException('certificado')]) {
        await expectLater(
          _crear(MockClient((_) async => throw error)),
          throwsA(isA<CobroPosnetException>().having((e) => e.incierto, 'incierto', true)),
          reason: '$error',
        );
      }
    });

    test('una respuesta que nunca llega vence (no cuelga el cobro)', () async {
      final original = plazoLlamadaMercadoPago;
      plazoLlamadaMercadoPago = const Duration(milliseconds: 50);
      addTearDown(() => plazoLlamadaMercadoPago = original);
      expect(original, const Duration(seconds: 25), reason: 'el plazo real no cambió');
      final client = MockClient((_) => Completer<http.Response>().future); // nunca contesta
      await expectLater(
        _crear(client),
        throwsA(isA<CobroPosnetException>().having((e) => e.incierto, 'incierto', true).having((e) => e.mensaje, 'mensaje', contains('a tiempo'))),
      );
    });

    test('un 5xx es incierto (quizá se creó); un 4xx es un rechazo definitivo', () async {
      await expectLater(
        _crear(MockClient((_) async => http.Response(jsonEncode({'message': 'internal'}), 503))),
        throwsA(isA<CobroPosnetException>().having((e) => e.incierto, 'incierto', true)),
      );
      await expectLater(
        _crear(MockClient((_) async => http.Response(jsonEncode({'message': 'terminal inválida'}), 400))),
        throwsA(isA<CobroPosnetException>().having((e) => e.incierto, 'incierto', false)),
      );
    });

    test('consultar y cancelar con la red caída también se traducen', () async {
      final caida = MockClient((_) async => throw const SocketException('sin red'));
      await expectLater(consultarOrden(accessToken: 't', ordenIdMp: 'ORD1', client: caida), throwsA(isA<CobroPosnetException>()));
      await expectLater(cancelarOrdenCobro(accessToken: 't', ordenIdMp: 'ORD1', client: caida), throwsA(isA<CobroPosnetException>()));
    });

    test('un id de orden raro no llega a la API (no se le manda el token a otro endpoint)', () async {
      var llamadas = 0;
      final client = MockClient((_) async {
        llamadas++;
        return http.Response('{}', 200);
      });
      for (final malo in ['../../users/me', 'a/b', 'ORD 1', '', 'x' * 65, 'ORD1?x=1']) {
        await expectLater(consultarOrden(accessToken: 't', ordenIdMp: malo, client: client), throwsA(isA<CobroPosnetException>()), reason: malo);
        await expectLater(cancelarOrdenCobro(accessToken: 't', ordenIdMp: malo, client: client), throwsA(isA<CobroPosnetException>()), reason: malo);
      }
      expect(llamadas, 0);
    });

    test('un id normal va codificado en la dirección', () async {
      Uri? pedida;
      final client = MockClient((r) async {
        pedida = r.url;
        return http.Response(jsonEncode({'status': 'processed'}), 200);
      });
      expect(await consultarOrden(accessToken: 't', ordenIdMp: 'ORD01K-abc_9', client: client), 'processed');
      expect(pedida.toString(), 'https://api.mercadopago.com/v1/orders/ORD01K-abc_9');
    });
  });

  group('iniciarOrdenDeCobro: el reintento después de un corte', () {
    late AppDatabase db;
    late int sesionId;

    setUp(() async {
      db = baseDeTest();
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    });
    tearDown(() => db.close());

    test('si se corta la red, el reintento usa la MISMA clave y referencia: Mercado Pago devuelve la misma orden', () async {
      final pasarela = _PasarelaFalsa([
        const CobroPosnetException('No hay conexión con Mercado Pago.', incierto: true),
        const OrdenCobroCreada(ordenIdMp: 'ORD1', estado: 'created'),
      ]);

      await expectLater(
        iniciarOrdenDeCobro(db, pasarela, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000),
        throwsA(isA<CobroPosnetException>()),
      );
      final reintento = await iniciarOrdenDeCobro(db, pasarela, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);

      expect(pasarela.claves, hasLength(2));
      expect(pasarela.claves[1], pasarela.claves[0]);
      expect(pasarela.referencias[1], pasarela.referencias[0]);
      expect(reintento.ordenIdMp, 'ORD1');
      final filas = await db.select(db.ordenesCobroPendientes).get();
      expect(filas, hasLength(1));
      expect(filas.single.ordenIdMp, 'ORD1');
      expect(filas.single.estado, 'pendiente');
    });

    test('un rechazo de Mercado Pago cierra el intento como rechazada (no queda como "sin resolver" en el cierre)', () async {
      final pasarela = _PasarelaFalsa([
        const CobroPosnetException('terminal inválida'),
        const OrdenCobroCreada(ordenIdMp: 'ORD2', estado: 'created'),
      ]);

      await expectLater(
        iniciarOrdenDeCobro(db, pasarela, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000),
        throwsA(isA<CobroPosnetException>()),
      );
      expect(await ordenesSinResolverDeSesion(db, sesionId), isEmpty);
      final rechazada = (await db.select(db.ordenesCobroPendientes).get()).single;
      expect(rechazada.estado, 'rechazada');

      // El reintento arranca de cero: otra clave, otra referencia.
      await iniciarOrdenDeCobro(db, pasarela, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      expect(pasarela.claves[1], isNot(pasarela.claves[0]));
    });

    test('un corte deja la orden visible en el cierre como "sin resolver" (nunca se asume que no se cobró)', () async {
      final pasarela = _PasarelaFalsa([const CobroPosnetException('sin red', incierto: true)]);
      await expectLater(
        iniciarOrdenDeCobro(db, pasarela, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000),
        throwsA(isA<CobroPosnetException>()),
      );
      expect(await ordenesSinResolverDeSesion(db, sesionId), hasLength(1));
    });
  });
}
