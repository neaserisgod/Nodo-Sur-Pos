import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/servicios/nombre_producto_ia.dart';

String _respuesta(String json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': json},
            ],
          },
        },
      ],
    });

void main() {
  test('el pedido lleva la descripción y hasta 20 ejemplos, nunca precios', () {
    final pedido = armarPedidoDeNombre('MRL BX 20 KS (10)', [for (var i = 0; i < 30; i++) 'Producto $i']);
    expect(pedido, contains('MRL BX 20 KS (10)'));
    expect(pedido, contains('Producto 19'));
    expect(pedido, isNot(contains('Producto 20')));
    expect(pedido, isNot(contains(r'$')));
  });

  test('lee el nombre y descarta respuestas vacías, rotas o desmedidas', () {
    expect(leerNombreDeIa({'nombre': '  Marlboro   Box 20  '}), 'Marlboro Box 20');
    expect(leerNombreDeIa({'nombre': ''}), isNull);
    expect(leerNombreDeIa({'otro': 'x'}), isNull);
    expect(leerNombreDeIa('nombre'), isNull);
    expect(leerNombreDeIa({'nombre': 'x' * 81}), isNull);
  });

  test('mejorarNombreConIa devuelve lo que contestó Gemini', () async {
    final cliente = ClienteGemini(apiKey: 'AIza-test', client: MockClient((_) async => http.Response(_respuesta('{"nombre":"Marlboro Box 20"}'), 200)));
    expect(await mejorarNombreConIa(cliente, descripcion: 'MRL BX 20 KS'), 'Marlboro Box 20');
  });

  test('sin nombre en la respuesta, avisa con un error legible', () async {
    final cliente = ClienteGemini(apiKey: 'AIza-test', client: MockClient((_) async => http.Response(_respuesta('{"nombre":""}'), 200)));
    expect(() => mejorarNombreConIa(cliente, descripcion: 'MRL BX 20 KS'), throwsA(isA<ErrorGemini>()));
  });
}
