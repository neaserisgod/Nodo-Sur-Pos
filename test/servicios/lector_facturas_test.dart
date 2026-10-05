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
    expect(url.path, contains(modeloParaLeerFacturas));
    expect(r.modelo, modeloParaLeerFacturas);
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
  });

  test('si el modelo fuerte no está para esta clave (404), prueba el que le anduvo al guardarla', () async {
    ClaveGemini.fijarParaTest('AIza-buena', modelo: 'gemini-3.5-flash-lite');
    final pedidos = <String>[];
    final r = await leerFacturasConGemini(
      [adjunto],
      client: MockClient((req) async {
        pedidos.add(req.url.path);
        return req.url.path.contains(modeloParaLeerFacturas) ? http.Response('{}', 404) : http.Response(_respuesta(_facturaElpar), 200);
      }),
    );
    expect(pedidos, hasLength(2));
    expect(r.modelo, 'gemini-3.5-flash-lite');
  });

  test('un fallo que no es 404 (sin cupo) se muestra tal cual, sin probar otro modelo', () async {
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
