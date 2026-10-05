import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _respuesta(String texto) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': texto},
            ],
          },
        },
      ],
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest(null);
  });

  group('ClaveGemini', () {
    test('guardar la persiste y cargar la recupera', () async {
      await ClaveGemini.guardar('  AIza-clave  ');
      expect(ClaveGemini.valor, 'AIza-clave');
      ClaveGemini.fijarParaTest(null);
      await ClaveGemini.cargar();
      expect(ClaveGemini.valor, 'AIza-clave');
      expect(ClaveGemini.configurada, isTrue);
    });

    test('guardar vacío la borra', () async {
      await ClaveGemini.guardar('AIza-clave');
      await ClaveGemini.guardar('   ');
      expect(ClaveGemini.configurada, isFalse);
      ClaveGemini.fijarParaTest('otra');
      await ClaveGemini.cargar();
      expect(ClaveGemini.valor, isNull);
    });

    test('ClienteGemini.guardado sin clave avisa dónde cargarla', () {
      expect(() => ClienteGemini.guardado(), throwsA(isA<ErrorGemini>()));
    });
  });

  group('generarTexto', () {
    test('manda la clave en el encabezado (no en la URL) y devuelve el texto', () async {
      late http.Request pedido;
      final cliente = ClienteGemini(
        apiKey: 'AIza-secreta',
        client: MockClient((r) async {
          pedido = r;
          return http.Response(_respuesta('hola'), 200);
        }),
      );
      final texto = await cliente.generarTexto('decí hola', sistema: 'sos un asistente');
      expect(texto, 'hola');
      expect(pedido.headers['x-goog-api-key'], 'AIza-secreta');
      expect(pedido.url.toString(), isNot(contains('AIza-secreta')));
      expect(pedido.url.path, endsWith('/models/$modeloGeminiPorDefecto:generateContent'));
      final cuerpo = jsonDecode(pedido.body) as Map<String, dynamic>;
      expect(cuerpo['systemInstruction']['parts'][0]['text'], 'sos un asistente');
      expect(cuerpo['contents'][0]['parts'][0]['text'], 'decí hola');
    });

    test('junta las partes de texto de la respuesta', () async {
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'uno '},
                        {'text': 'dos'},
                      ],
                    },
                  },
                ],
              }),
              200,
            )),
      );
      expect(await cliente.generarTexto('x'), 'uno dos');
    });

    test('respuesta bloqueada por Google: avisa el motivo', () async {
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(jsonEncode({'promptFeedback': {'blockReason': 'SAFETY'}}), 200)),
      );
      expect(
        cliente.generarTexto('x'),
        throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('SAFETY'))),
      );
    });

    test('sin candidatos ni bloqueo: no devuelve vacío en silencio', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => http.Response('{}', 200)));
      expect(cliente.generarTexto('x'), throwsA(isA<ErrorGemini>()));
    });
  });

  group('errores', () {
    Future<String> mensajeDe(int estado, [String cuerpo = '{}']) async {
      final cliente = ClienteGemini(apiKey: 'AIza-secreta', client: MockClient((_) async => http.Response(cuerpo, estado)));
      try {
        await cliente.generarTexto('x');
      } on ErrorGemini catch (e) {
        return e.mensaje;
      }
      fail('tenía que fallar');
    }

    test('clave mal escrita (Google contesta 400)', () async {
      final m = await mensajeDe(400, jsonEncode({'error': {'message': 'API key not valid. Please pass a valid API key.'}}));
      expect(m, contains('clave no es válida'));
    });

    test('sin cupo gratis (429)', () async => expect(await mensajeDe(429), contains('cupo gratis')));
    test('modelo retirado (404) nombra el modelo', () async => expect(await mensajeDe(404), contains(modeloGeminiPorDefecto)));
    test('error de Google (503)', () async => expect(await mensajeDe(503), contains('Google')));

    test('ningún mensaje de error lleva la clave', () async {
      for (final estado in [400, 401, 403, 404, 429, 500]) {
        expect(await mensajeDe(estado), isNot(contains('AIza-secreta')));
      }
    });

    test('sin internet', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => throw const SocketException('sin red')));
      expect(
        cliente.generarTexto('x'),
        throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('internet'))),
      );
    });
  });

  group('generarJson y probar', () {
    test('decodifica el JSON y lo pide como application/json', () async {
      late Map<String, dynamic> cuerpo;
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((r) async {
          cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(_respuesta('{"promos": [1, 2]}'), 200);
        }),
      );
      final json = await cliente.generarJson('x') as Map;
      expect(json['promos'], [1, 2]);
      expect(cuerpo['generationConfig']['responseMimeType'], 'application/json');
    });

    test('JSON roto: ErrorGemini, no FormatException', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => http.Response(_respuesta('no es json'), 200)));
      expect(cliente.generarJson('x'), throwsA(isA<ErrorGemini>()));
    });

    test('probar: null si anda, el motivo si no', () async {
      final bien = ClienteGemini(apiKey: 'k', client: MockClient((_) async => http.Response(_respuesta('ok'), 200)));
      expect(await bien.probar(), isNull);
      final mal = ClienteGemini(apiKey: 'k', client: MockClient((_) async => http.Response('{}', 429)));
      expect(await mal.probar(), contains('cupo gratis'));
    });
  });

  group('probarYGuardarClave', () {
    test('una clave que anda se guarda, con el primer modelo que le anduvo', () async {
      final r = await probarYGuardarClave(' AIza-buena ', client: MockClient((_) async => http.Response(_respuesta('ok'), 200)));
      expect(r, isNull);
      expect(ClaveGemini.valor, 'AIza-buena');
      expect(ClaveGemini.modelo, modelosGemini.first);
    });

    test('si el primer modelo da 404 (cuenta nueva con los 2.5, o modelo retirado), prueba el siguiente y guarda ese', () async {
      final pedidos = <String>[];
      final r = await probarYGuardarClave(
        'AIza-buena',
        client: MockClient((req) async {
          pedidos.add(req.url.path);
          return req.url.path.contains(modelosGemini.first) ? http.Response('{"error":{"message":"not found"}}', 404) : http.Response(_respuesta('ok'), 200);
        }),
      );
      expect(r, isNull);
      expect(ClaveGemini.modelo, modelosGemini[1]);
      expect(pedidos, hasLength(2));
    });

    test('si ningún modelo está disponible, lo dice y no guarda la clave', () async {
      final r = await probarYGuardarClave('AIza-buena', client: MockClient((_) async => http.Response('{}', 404)));
      expect(r, contains('Ningún modelo gratuito'));
      expect(ClaveGemini.configurada, isFalse);
    });

    test('un fallo que no es 404 (sin cupo) corta ahí: no se prueban los demás modelos', () async {
      var pedidos = 0;
      final r = await probarYGuardarClave(
        'AIza-buena',
        client: MockClient((_) async {
          pedidos++;
          return http.Response('{}', 429);
        }),
      );
      expect(r, contains('cupo gratis'));
      expect(pedidos, 1);
    });

    test('la clave guardada recuerda el modelo después de reiniciar', () async {
      await ClaveGemini.guardar('AIza-buena', modelo: 'gemini-3.8-flash');
      ClaveGemini.fijarParaTest(null);
      await ClaveGemini.cargar();
      expect(ClaveGemini.modelo, 'gemini-3.8-flash');
      expect(ClienteGemini.guardado().modelo, 'gemini-3.8-flash');
    });

    test('elegirModelo cambia solo el modelo, lo recuerda al reiniciar y no hace nada sin clave', () async {
      await ClaveGemini.elegirModelo('gemini-3.8-flash');
      expect(ClaveGemini.modelo, isNull); // sin clave no hay a qué asociarlo

      await ClaveGemini.guardar('AIza-buena', modelo: 'gemini-3.5-flash-lite');
      await ClaveGemini.elegirModelo('gemini-3.8-flash');
      expect(ClaveGemini.valor, 'AIza-buena');
      ClaveGemini.fijarParaTest(null);
      await ClaveGemini.cargar();
      expect(ClaveGemini.modelo, 'gemini-3.8-flash');
    });

    test('etiquetaDeModelo agrega la nota, y un modelo desconocido se muestra con su nombre', () {
      expect(etiquetaDeModelo('gemini-3.5-flash-lite'), contains('barato'));
      expect(etiquetaDeModelo('gemini-9'), 'gemini-9');
    });

    test('quitar la clave borra también el modelo', () async {
      await ClaveGemini.guardar('AIza-buena', modelo: 'gemini-3.8-flash');
      await ClaveGemini.guardar(null);
      expect(ClaveGemini.modelo, isNull);
    });

    test('una clave rota NO se guarda y no pisa la anterior', () async {
      await ClaveGemini.guardar('AIza-vieja');
      final r = await probarYGuardarClave('AIza-rota', client: MockClient((_) async => http.Response('{"error":{"message":"API key not valid"}}', 400)));
      expect(r, contains('clave no es válida'));
      expect(ClaveGemini.valor, 'AIza-vieja');
    });

    test('vacía borra la clave sin llamar a Google', () async {
      await ClaveGemini.guardar('AIza-vieja');
      final r = await probarYGuardarClave('  ', client: MockClient((_) async => fail('no tenía que llamar a Google')));
      expect(r, isNull);
      expect(ClaveGemini.configurada, isFalse);
    });
  });

  group('adjuntos (fotos y PDF)', () {
    test('van como inlineData en base64, después del texto', () async {
      late Map<String, dynamic> cuerpo;
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((r) async {
          cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(_respuesta('ok'), 200);
        }),
      );
      await cliente.generarTexto('leé esto', adjuntos: [
        AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3])),
        AdjuntoGemini('application/pdf', Uint8List.fromList([4, 5])),
      ]);
      final partes = cuerpo['contents'][0]['parts'] as List;
      expect(partes[0]['text'], 'leé esto');
      expect(partes[1]['inlineData']['mimeType'], 'image/jpeg');
      expect(partes[1]['inlineData']['data'], base64Encode([1, 2, 3]));
      expect(partes[2]['inlineData']['mimeType'], 'application/pdf');
    });

    test('si pesan demasiado, avisa sin mandar nada', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => fail('no tenía que llamar a Google')));
      expect(
        cliente.generarTexto('x', adjuntos: [AdjuntoGemini('image/jpeg', Uint8List(maximoBytesAdjuntosGemini + 1))]),
        throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('pesan demasiado'))),
      );
    });

    test('sin adjuntos el pedido sigue siendo solo texto', () async {
      late Map<String, dynamic> cuerpo;
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((r) async {
          cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response(_respuesta('ok'), 200);
        }),
      );
      await cliente.generarTexto('hola');
      expect((cuerpo['contents'][0]['parts'] as List), hasLength(1));
    });
  });
}
