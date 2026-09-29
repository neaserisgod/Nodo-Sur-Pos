import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/cobro_posnet.dart';

void main() {
  group('crearOrdenCobro', () {
    test('manda el POST correcto a la Orders API de Mercado Pago', () async {
      http.Request? capturada;
      final client = MockClient((request) async {
        capturada = request;
        return http.Response(
          jsonEncode({'id': 'orden123', 'status': 'created'}),
          201,
        );
      });

      final creada = await crearOrdenCobro(
        accessToken: 'TOKEN123',
        terminalId: 'N950NCC503383252',
        externalReference: 'ext-ref-uuid',
        idempotencyKey: 'idem-key-uuid',
        montoCentavos: 174050,
        canal: 'qr',
        client: client,
      );

      expect(capturada, isNotNull);
      expect(capturada!.method, 'POST');
      expect(
        capturada!.url.toString(),
        'https://api.mercadopago.com/v1/orders',
      );
      expect(capturada!.headers['Authorization'], 'Bearer TOKEN123');
      expect(capturada!.headers['Content-Type'], contains('application/json'));
      expect(capturada!.headers['X-Idempotency-Key'], 'idem-key-uuid');

      final body = jsonDecode(capturada!.body) as Map<String, dynamic>;
      expect(body['type'], 'point');
      expect(body['external_reference'], 'ext-ref-uuid');
      expect(
        body['transactions']['payments'][0]['amount'],
        '1740.50',
      ); // nunca centavos
      expect(body['config']['point']['terminal_id'], 'N950NCC503383252');
      expect(body['config']['point']['print_on_terminal'], 'no_ticket');
      expect(body['config']['payment_method']['default_type'], 'qr');

      expect(creada.ordenIdMp, 'orden123');
      expect(creada.estado, 'created');
    });

    test('canal débito manda default_type: debit_card', () async {
      http.Request? capturada;
      final client = MockClient((request) async {
        capturada = request;
        return http.Response(jsonEncode({'id': 'x', 'status': 'created'}), 201);
      });

      await crearOrdenCobro(
        accessToken: 't',
        terminalId: 'x',
        externalReference: 'x',
        idempotencyKey: 'x',
        montoCentavos: 100000,
        canal: 'debit_card',
        client: client,
      );

      final body = jsonDecode(capturada!.body) as Map<String, dynamic>;
      expect(body['config']['payment_method']['default_type'], 'debit_card');
    });

    test(
      'un error de la API se traduce a CobroPosnetException con el mensaje de MercadoPago',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'message': 'invalid terminal_id'}),
            400,
          );
        });

        await expectLater(
          () => crearOrdenCobro(
            accessToken: 't',
            terminalId: 'inexistente',
            externalReference: 'x',
            idempotencyKey: 'x',
            montoCentavos: 100000,
            canal: 'qr',
            client: client,
          ),
          throwsA(
            isA<CobroPosnetException>().having(
              (e) => e.toString(),
              'mensaje',
              contains('invalid terminal_id'),
            ),
          ),
        );
      },
    );

    test(
      'un error en formato {"errors": [...]} (el que devuelve MP de verdad) también se entiende',
      () async {
        // Caso real (Bruno probó contra el posnet): MP no siempre manda
        // {"message": "..."} — para validaciones y para el cancel manda
        // {"errors": [{"code", "message"}]}. Antes de esto se mostraba el
        // JSON crudo entero en vez del mensaje.
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'code': 'property_value',
                  'message': 'Invalid value for property',
                  'details': [
                    "'\$.config.point.terminal_id' - does not match pattern",
                  ],
                },
              ],
            }),
            400,
          );
        });

        await expectLater(
          () => crearOrdenCobro(
            accessToken: 't',
            terminalId: 'N950NCC503383252',
            externalReference: 'x',
            idempotencyKey: 'x',
            montoCentavos: 100000,
            canal: 'qr',
            client: client,
          ),
          throwsA(
            isA<CobroPosnetException>().having(
              (e) => e.toString(),
              'mensaje',
              contains('Invalid value for property'),
            ),
          ),
        );
      },
    );
  });

  group('consultarOrden', () {
    test('devuelve el status de la orden', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://api.mercadopago.com/v1/orders/orden123',
        );
        expect(request.headers['Authorization'], 'Bearer t');
        return http.Response(
          jsonEncode({'id': 'orden123', 'status': 'processed'}),
          200,
        );
      });

      final estado = await consultarOrden(
        accessToken: 't',
        ordenIdMp: 'orden123',
        client: client,
      );

      expect(estado, 'processed');
    });

    test('un error de la API se traduce a CobroPosnetException', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'message': 'order not found'}), 404);
      });

      await expectLater(
        () => consultarOrden(
          accessToken: 't',
          ordenIdMp: 'inexistente',
          client: client,
        ),
        throwsA(
          isA<CobroPosnetException>().having(
            (e) => e.toString(),
            'mensaje',
            contains('order not found'),
          ),
        ),
      );
    });
  });

  group('cancelarOrdenCobro', () {
    test('manda el POST correcto a .../orders/{id}/cancel', () async {
      http.Request? capturada;
      final client = MockClient((request) async {
        capturada = request;
        return http.Response('{}', 200);
      });

      await cancelarOrdenCobro(
        accessToken: 'TOKEN123',
        ordenIdMp: 'orden123',
        client: client,
      );

      expect(capturada, isNotNull);
      expect(capturada!.method, 'POST');
      expect(
        capturada!.url.toString(),
        'https://api.mercadopago.com/v1/orders/orden123/cancel',
      );
      expect(capturada!.headers['Authorization'], 'Bearer TOKEN123');
      expect(capturada!.headers['X-Idempotency-Key'], isNotEmpty);
    });

    test('un error de la API se traduce a CobroPosnetException', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'order already resolved'}),
          404,
        );
      });

      await expectLater(
        () => cancelarOrdenCobro(
          accessToken: 't',
          ordenIdMp: 'orden123',
          client: client,
        ),
        throwsA(
          isA<CobroPosnetException>().having(
            (e) => e.toString(),
            'mensaje',
            contains('order already resolved'),
          ),
        ),
      );
    });

    test(
      'cannot_cancel_order (orden ya en la terminal) da un mensaje de negocio, no el JSON crudo',
      () async {
        // Caso real contra el posnet de Bruno: la orden pasa a `at_terminal`
        // casi al instante de crearse, y desde ahí MP ya no permite
        // cancelarla por API — 409, código `cannot_cancel_order`.
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'code': 'cannot_cancel_order',
                  'message':
                      "the order cannot be canceled because the current status, 'at_terminal', doesn't allow cancelation",
                },
              ],
            }),
            409,
          );
        });

        await expectLater(
          () => cancelarOrdenCobro(
            accessToken: 't',
            ordenIdMp: 'orden123',
            client: client,
          ),
          throwsA(
            isA<CobroPosnetException>().having(
              (e) => e.toString(),
              'mensaje',
              allOf(
                contains('Mercado Pago no permite cancelarla por API'),
                isNot(contains('errors')),
              ),
            ),
          ),
        );
      },
    );
  });
}
