import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/impresion_posnet.dart';
import 'package:la_plazoleta/domain/ticket.dart';

void main() {
  final ticket = construirTicket(
    fecha: DateTime(2026, 8, 30, 15, 0),
    vendedor: 'Bruno',
    lineas: const [
      LineaTicket(nombreProducto: 'Coca-Cola 500ml', cantidad: 2, subtotalCentavos: 224000),
    ],
    desglose: const DesgloseTicket(),
  );

  test('manda el POST correcto a la API de Terminals de MercadoPago', () async {
    http.Request? capturada;
    final client = MockClient((request) async {
      capturada = request;
      return http.Response('{}', 200);
    });

    await imprimirEnPosnet(
      accessToken: 'TOKEN123',
      terminalId: 'NEWLAND_N950__N950NCC503383252',
      ticket: ticket,
      encabezadoNegocio: 'La Plazoleta',
      client: client,
    );

    expect(capturada, isNotNull);
    expect(capturada!.url.toString(), 'https://api.mercadopago.com/terminals/v1/actions');
    expect(capturada!.headers['Authorization'], 'Bearer TOKEN123');
    expect(capturada!.headers['Content-Type'], contains('application/json'));
    expect(capturada!.headers['X-Idempotency-Key'], isNotEmpty);

    final body = jsonDecode(capturada!.body) as Map<String, dynamic>;
    expect(body['type'], 'print');
    expect(body['config']['point']['terminal_id'], 'NEWLAND_N950__N950NCC503383252');
    expect(body['config']['point']['subtype'], 'custom');
    expect(body['content'], contains('La Plazoleta'));
    expect(body['content'], contains('Coca-Cola 500ml'));
  });

  test('dos llamadas usan una X-Idempotency-Key distinta cada vez', () async {
    final headers = <String>[];
    final client = MockClient((request) async {
      headers.add(request.headers['X-Idempotency-Key']!);
      return http.Response('{}', 200);
    });

    await imprimirEnPosnet(
      accessToken: 't',
      terminalId: 'x',
      ticket: ticket,
      encabezadoNegocio: 'x',
      client: client,
    );
    await imprimirEnPosnet(
      accessToken: 't',
      terminalId: 'x',
      ticket: ticket,
      encabezadoNegocio: 'x',
      client: client,
    );

    expect(headers[0], isNot(headers[1]));
  });

  test('un error de la API se traduce a ImpresionPosnetException con el mensaje de MercadoPago', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'message': 'terminal not found'}), 404);
    });

    await expectLater(
      () => imprimirEnPosnet(
        accessToken: 't',
        terminalId: 'inexistente',
        ticket: ticket,
        encabezadoNegocio: 'x',
        client: client,
      ),
      throwsA(isA<ImpresionPosnetException>().having((e) => e.toString(), 'mensaje', contains('terminal not found'))),
    );
  });

  test('un 200 no tira ninguna excepción', () async {
    final client = MockClient((request) async => http.Response('{}', 200));

    await imprimirEnPosnet(
      accessToken: 't',
      terminalId: 'x',
      ticket: ticket,
      encabezadoNegocio: 'x',
      client: client,
    );
  });
}
