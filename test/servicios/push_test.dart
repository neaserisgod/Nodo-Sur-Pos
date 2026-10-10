// Notificaciones con la app cerrada (`push.dart`): el celular registra su token en el sitio una vez por sesión, solo en Android y
// solo con el proyecto de Firebase cargado; si Android no da token (sin Google Play Services), no rompe nada.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('nodosur/push-test');
  const opciones = OpcionesFirebase(apiKey: 'AIza-x', appId: '1:123:android:abc', senderId: '123', projectId: 'nodo-sur');
  late List<String> llamadas;
  late List<Map<String, dynamic>> registrados;
  late String? token;
  late ClienteNube cliente;

  setUp(() {
    llamadas = [];
    registrados = [];
    token = 'fcm-token-1234567890abcdef';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      llamadas.add(c.method);
      if (c.method == 'token') {
        expect(c.arguments, opciones.toJson());
        if (token == null) throw PlatformException(code: 'sin_token');
        return token;
      }
      return null;
    });
    cliente = ClienteNube(http: MockClient((r) async {
      expect(r.url.path, '/api/device/push');
      expect(r.headers['Authorization'], 'Bearer tok-cuenta');
      registrados.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response('{"ok":true}', 200);
    }));
  });

  test('pide el permiso, saca el token y lo registra una sola vez', () async {
    final push = RegistroPush(cliente: cliente, opciones: opciones, canal: canal, esAndroid: true);
    expect(await push.registrarSiHaceFalta('tok-cuenta'), isTrue);
    expect(registrados, [{'token': 'fcm-token-1234567890abcdef'}]);
    expect(await push.registrarSiHaceFalta('tok-cuenta'), isFalse);
    expect(registrados, hasLength(1));
    expect(llamadas.where((m) => m == 'pedirPermiso'), hasLength(1));
    token = 'fcm-token-nuevo-0987654321';
    expect(await push.registrarSiHaceFalta('tok-cuenta'), isTrue, reason: 'si cambió el token, se vuelve a registrar');
  });

  test('sin los datos del proyecto de Firebase, o fuera de Android, no hace nada', () async {
    expect(await RegistroPush(cliente: cliente, opciones: const OpcionesFirebase(apiKey: '', appId: '', senderId: '', projectId: ''), canal: canal, esAndroid: true).registrarSiHaceFalta('tok-cuenta'), isFalse);
    expect(await RegistroPush(cliente: cliente, opciones: opciones, canal: canal, esAndroid: false).registrarSiHaceFalta('tok-cuenta'), isFalse);
    expect(llamadas, isEmpty);
    expect(registrados, isEmpty);
  });

  test('si Android no da token, no rompe', () async {
    token = null;
    expect(await RegistroPush(cliente: cliente, opciones: opciones, canal: canal, esAndroid: true).registrarSiHaceFalta('tok-cuenta'), isFalse);
    expect(registrados, isEmpty);
  });
}
