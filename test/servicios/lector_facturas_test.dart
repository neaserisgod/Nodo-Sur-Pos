import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/servicios/lector_facturas.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const _facturaElpar =
    '{"facturas":[{"proveedor":{"razon_social":"Distribuidora ELPAR srl","cuit":"30-70817475-7"},"tipo":"A","numero":"0011-00266439",'
    '"fecha":"2026-07-24","condicion_pago":"cuenta_corriente","lineas":[{"descripcion":"CREMA SIMPLE X 200 GR (24)","cantidad":4,'
    '"precio_unitario":1908.26,"descuento_pct":5,"importe":7251.41}],"pie":{"total":8774.2}}]}';

void main() {
  final adjunto = AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3]));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest('AIza-buena');
  });

  test('manda la foto con las instrucciones de lectura y devuelve lo leído', () async {
    late Map<String, dynamic> cuerpo;
    late Uri url;
    final r = await leerFacturasConGemini(
      [adjunto],
      client: MockClient((req) async {
        cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
        url = req.url;
        return http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(url.path, contains(modeloGeminiPorDefecto));
    expect(r.modelo, modeloGeminiPorDefecto);
    expect(cuerpo['systemInstruction']['parts'][0]['text'], instruccionesDeLecturaDeFacturas);
    expect((cuerpo['contents'][0]['parts'] as List)[1]['inlineData']['mimeType'], 'image/jpeg');
    expect(cuerpo['generationConfig']['temperature'], 0);
    expect(r.lectura.facturas.single.proveedorCuit, '30708174757');
    expect(r.lectura.facturas.single.lineas.single.importeCentavos, 725141);
    expect((r.json as Map)['facturas'], isNotEmpty);
  });

  test('las instrucciones piden ignorar lo escrito a mano y los datos del comprador', () {
    expect(instruccionesDeLecturaDeFacturas, contains('IGNORÁ todo lo escrito a mano'));
    expect(instruccionesDeLecturaDeFacturas, contains('NO transcribas los datos del comprador'));
    expect(instruccionesDeLecturaDeFacturas, contains('MÁS DE UNA factura'));
    expect(instruccionesDeLecturaDeFacturas, contains('descuento_importe')); // el monto de un descuento no va en el campo del porcentaje
  });

  test('lee con el modelo que el dueño eligió, no con el más nuevo', () async {
    ClaveGemini.fijarParaTest('AIza-buena', modelo: 'gemini-3.1-flash-lite');
    late Uri url;
    final r = await leerFacturasConGemini(
      [adjunto],
      client: MockClient((req) async {
        url = req.url;
        return http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(url.path, contains('gemini-3.1-flash-lite'));
    expect(r.modelo, 'gemini-3.1-flash-lite');
  });

  test('si el elegido no está para esta clave (404), prueba el de respaldo', () async {
    ClaveGemini.fijarParaTest('AIza-buena', modelo: 'gemini-3.5-flash-lite');
    final pedidos = <String>[];
    final r = await leerFacturasConGemini(
      [adjunto],
      client: MockClient((req) async {
        pedidos.add(req.url.path);
        return req.url.path.contains(modeloGeminiPorDefecto) ? http.Response('{}', 404) : http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(pedidos, hasLength(2));
    expect(r.modelo, modeloDeRespaldoParaFacturas);
  });

  test('sin cupo en el modelo fuerte (429), prueba el liviano, que tiene su propio cupo', () async {
    final pedidos = <String>[];
    final r = await leerFacturasConGemini(
      [adjunto],
      client: MockClient((req) async {
        pedidos.add(req.url.path);
        return req.url.path.contains(modeloGeminiPorDefecto) ? http.Response('{}', 429) : http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(pedidos, hasLength(2));
    expect(r.modelo, isNot(modeloGeminiPorDefecto));
  });

  test('sin cupo en los dos modelos, avisa que se acabó el cupo gratis', () async {
    var pedidos = 0;
    await expectLater(
      leerFacturasConGemini(
        [adjunto],
        client: MockClient((_) async {
          pedidos++;
          return http.Response('{}', 429);
        }),
      ),
      throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('cupo gratis'))),
    );
    expect(pedidos, 2); // un 429 no se reintenta: pasa al otro modelo y listo
  });

  test('si Google está saturado (503), reintenta una vez el mismo modelo y anda', () async {
    final pedidos = <String>[];
    final r = await leerFacturasConGemini(
      [adjunto],
      espera: Duration.zero,
      client: MockClient((req) async {
        pedidos.add(req.url.path);
        return pedidos.length == 1 ? http.Response('{"error":{"message":"The model is overloaded."}}', 503) : http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(pedidos, hasLength(2));
    expect(pedidos.toSet(), hasLength(1)); // el mismo modelo las dos veces
    expect(r.modelo, modeloGeminiPorDefecto);
  });

  test('si el modelo fuerte sigue saturado, pasa al liviano', () async {
    final pedidos = <String>[];
    final r = await leerFacturasConGemini(
      [adjunto],
      espera: Duration.zero,
      client: MockClient((req) async {
        pedidos.add(req.url.path);
        return req.url.path.contains(modeloGeminiPorDefecto) ? http.Response('{}', 503) : http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(pedidos, hasLength(3)); // fuerte, fuerte (reintento), liviano
    expect(r.modelo, isNot(modeloGeminiPorDefecto));
  });

  test('si todo está caído, el mensaje trae el detalle que manda Google', () async {
    await expectLater(
      leerFacturasConGemini(
        [adjunto],
        espera: Duration.zero,
        client: MockClient((_) async => http.Response('{"error":{"message":"The model is overloaded. Please try again later."}}', 503)),
      ),
      throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', allOf(contains('503'), contains('overloaded')))),
    );
  });

  test('una clave mala (400) no prueba otro modelo ni reintenta', () async {
    var pedidos = 0;
    await expectLater(
      leerFacturasConGemini(
        [adjunto],
        client: MockClient((_) async {
          pedidos++;
          return http.Response('{"error":{"message":"API key not valid"}}', 400);
        }),
      ),
      throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('clave no es válida'))),
    );
    expect(pedidos, 1);
  });

  test('sin clave, avisa dónde cargarla', () async {
    ClaveGemini.fijarParaTest(null);
    await expectLater(
      leerFacturasConGemini([adjunto], client: MockClient((_) async => fail('no tenía que llamar a Google'))),
      throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('Asistente IA'))),
    );
  });

  test('sin archivos no llama a Google', () async {
    await expectLater(
      leerFacturasConGemini(const [], client: MockClient((_) async => fail('no tenía que llamar a Google'))),
      throwsA(isA<ErrorGemini>()),
    );
  });

  test('una respuesta que no es JSON se informa como error legible, no como excepción rara', () async {
    await expectLater(
      leerFacturasConGemini([adjunto], client: MockClient((_) async => http.Response(_respuesta('no es json'), 200))),
      throwsA(isA<ErrorGemini>()),
    );
  });
}
