import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/servicios/ia_nube.dart';
import 'package:la_plazoleta/servicios/lector_facturas.dart';
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

/// La cuenta del negocio simulada: guarda la clave y contesta lo que diga [responder].
class _CuentaFalsa implements AccesoIaCuenta {
  _CuentaFalsa({this.configurada = false, this.puedeCambiar = true, this.modelo});
  bool configurada;
  bool puedeCambiar;
  String? modelo;
  String? clave;
  final pedidos = <({String modelo, String cuerpo})>[];
  ({int estado, String cuerpo}) Function(String modelo) responder = (_) => (estado: 200, cuerpo: _respuesta('ok'));

  @override
  Future<({bool configurada, String? modelo, bool puedeCambiar})?> estado() async =>
      (configurada: configurada, modelo: modelo, puedeCambiar: puedeCambiar);

  @override
  Future<void> guardarClave(String? clave, {String? modelo}) async {
    this.clave = clave;
    this.modelo = modelo;
    configurada = clave != null;
  }

  @override
  Future<({int estado, String cuerpo})> generar({required String modelo, required String cuerpo, required Duration limite}) async {
    pedidos.add((modelo: modelo, cuerpo: cuerpo));
    return responder(modelo);
  }
}

/// La clave de la IA es del negocio (El dueño, 2026-10-07: "la clave es por cuenta").
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest(null);
  });

  test('sin clave propia, con la del negocio, el pedido sale por la cuenta y la respuesta se lee igual', () async {
    final cuenta = _CuentaFalsa(configurada: true, puedeCambiar: false, modelo: 'gemini-3.5-flash-lite');
    await ClaveGemini.conectarCuenta(cuenta);
    expect(ClaveGemini.configurada, isTrue);
    expect(ClaveGemini.enCuenta, isTrue);
    expect(ClaveGemini.modelo, 'gemini-3.5-flash-lite');

    final texto = await ClienteGemini.guardado().generarTexto('Hola', sistema: 'Sos un almacén');
    expect(texto, 'ok');
    final pedido = cuenta.pedidos.single;
    expect(pedido.modelo, 'gemini-3.5-flash-lite');
    final cuerpo = jsonDecode(pedido.cuerpo) as Map<String, dynamic>;
    expect(cuerpo['systemInstruction'], isNotNull, reason: 'el pedido es el mismo que iría directo a Google');
  });

  test('un error de Google que vuelve por la cuenta se explica igual (sin cupo)', () async {
    final cuenta = _CuentaFalsa(configurada: true)..responder = (_) => (estado: 429, cuerpo: '{"error":{"message":"exhausted"}}');
    await ClaveGemini.conectarCuenta(cuenta);
    await expectLater(
      ClienteGemini.guardado().generarTexto('Hola'),
      throwsA(isA<ErrorGemini>().having((e) => e.estado, 'estado', 429).having((e) => e.mensaje, 'mensaje', contains('cupo'))),
    );
  });

  test('una clave propia de este equipo (instalación vieja) sigue mandando directo a Google', () async {
    final cuenta = _CuentaFalsa(configurada: true);
    await ClaveGemini.conectarCuenta(cuenta);
    await ClaveGemini.guardar('AIza-propia', modelo: 'gemini-3.5-flash-lite');
    String? claveUsada;
    final directo = MockClient((r) async {
      claveUsada = r.headers['x-goog-api-key'];
      return http.Response(_respuesta('directo'), 200);
    });
    expect(await ClienteGemini.guardado(client: directo).generarTexto('Hola'), 'directo');
    expect(claveUsada, 'AIza-propia');
    expect(cuenta.pedidos, isEmpty);
  });

  test('el dueño guarda la clave EN LA CUENTA: se prueba con Google, se sube con el modelo que anduvo y no queda en este equipo', () async {
    final cuenta = _CuentaFalsa(puedeCambiar: true);
    await ClaveGemini.conectarCuenta(cuenta);
    final google = MockClient((r) async => http.Response(_respuesta('ok'), 200));

    expect(await probarYGuardarClave('  AIza-del-negocio  ', client: google), isNull);
    expect(cuenta.clave, 'AIza-del-negocio');
    expect(cuenta.modelo, modelosGemini.first);
    expect(ClaveGemini.valor, isNull, reason: 'una sola clave: la del negocio');
    expect(ClaveGemini.enCuenta, isTrue);

    // Al reabrir la app sin internet se sigue sabiendo que el negocio tiene clave.
    ClaveGemini.fijarParaTest(null);
    await ClaveGemini.cargar();
    await ClaveGemini.conectarCuenta(_CuentaQueNoContesta());
    expect(ClaveGemini.configurada, isTrue);

    // Quitarla la borra de la cuenta.
    await ClaveGemini.conectarCuenta(cuenta);
    expect(await probarYGuardarClave(''), isNull);
    expect(cuenta.clave, isNull);
    expect(ClaveGemini.configurada, isFalse);
  });

  test('un empleado vinculado (no puede cambiarla) guarda una clave solo en su equipo, sin tocar la del negocio', () async {
    final cuenta = _CuentaFalsa(puedeCambiar: false);
    await ClaveGemini.conectarCuenta(cuenta);
    final google = MockClient((r) async => http.Response(_respuesta('ok'), 200));
    expect(await probarYGuardarClave('AIza-mia', client: google), isNull);
    expect(cuenta.clave, isNull);
    expect(ClaveGemini.valor, 'AIza-mia');
  });

  test('leer una factura con la clave del negocio pasa por la cuenta', () async {
    final cuenta = _CuentaFalsa(configurada: true)
      ..responder = (_) => (estado: 200, cuerpo: _respuesta('{"facturas":[]}'));
    await ClaveGemini.conectarCuenta(cuenta);
    final r = await leerFacturasConGemini([AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3]))]);
    expect(r.lectura.facturas, isEmpty);
    expect(cuenta.pedidos.single.cuerpo, contains('inlineData'), reason: 'la foto va en el pedido');
  });

  group('AccesoIaNube contra el sitio', () {
    AccesoIaNube acceso(MockClient http) {
      final almacen = AlmacenCuentaEnMemoria();
      almacen.guardar(const CuentaVinculada(token: 'tok', email: 'd@x.com', idDispositivo: 'pc', nombreDispositivo: 'PC', vence: 0));
      return AccesoIaNube(() async => (almacen: almacen as AlmacenCuenta, cliente: ClienteNube(http: http)));
    }

    test('un error del sitio (el negocio no tiene clave) se explica; uno de Google vuelve tal cual', () async {
      var deGoogle = false;
      final sitio = MockClient((r) async {
        expect(r.url.path, '/api/ia/generar');
        expect(r.headers['Authorization'], 'Bearer tok');
        return deGoogle ? http.Response('{"error":{"message":"overloaded"}}', 503) : http.Response('{"error":"ia_sin_clave"}', 409);
      });
      await expectLater(
        acceso(sitio).generar(modelo: 'm', cuerpo: '{}', limite: const Duration(seconds: 5)),
        throwsA(isA<ErrorGemini>().having((e) => e.mensaje, 'mensaje', contains('dueño'))),
      );
      deGoogle = true;
      final r = await acceso(sitio).generar(modelo: 'm', cuerpo: '{}', limite: const Duration(seconds: 5));
      expect(r.estado, 503);
    });

    test('estado y guardar la clave', () async {
      Map<String, dynamic>? enviado;
      final sitio = MockClient((r) async {
        if (r.url.path == '/api/ia/estado') return http.Response('{"configured":true,"model":"gemini-3.5-flash-lite","canChange":true}', 200);
        enviado = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      });
      final e = await acceso(sitio).estado();
      expect(e, (configurada: true, modelo: 'gemini-3.5-flash-lite', puedeCambiar: true));
      await acceso(sitio).guardarClave('AIza-x', modelo: 'gemini-3.5-flash-lite');
      expect(enviado, {'clave': 'AIza-x', 'modelo': 'gemini-3.5-flash-lite'});
    });
  });
}

class _CuentaQueNoContesta implements AccesoIaCuenta {
  @override
  Future<({bool configurada, String? modelo, bool puedeCambiar})?> estado() => throw const ErrorGemini('sin red');
  @override
  Future<void> guardarClave(String? clave, {String? modelo}) => throw const ErrorGemini('sin red');
  @override
  Future<({int estado, String cuerpo})> generar({required String modelo, required String cuerpo, required Duration limite}) =>
      throw const ErrorGemini('sin red');
}
