import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/domain/actualizacion.dart';
import 'package:la_plazoleta/servicios/actualizaciones.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _feed(String version) =>
    '<rss><channel><item><enclosure sparkle:version="$version" /></item></channel></rss>';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('idClienteActualizaciones', () {
    test('genera uno la primera vez y devuelve siempre el mismo', () async {
      final primero = await idClienteActualizaciones();
      final segundo = await idClienteActualizaciones();
      expect(primero, isNotEmpty);
      expect(segundo, primero);
    });

    test('lo guarda: una instancia nueva de prefs lo lee', () async {
      final primero = await idClienteActualizaciones();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('actualizaciones_cid'), primero);
    });

    test('respeta uno ya guardado', () async {
      SharedPreferences.setMockInitialValues({'actualizaciones_cid': 'fijo123'});
      expect(await idClienteActualizaciones(), 'fijo123');
    });

    test('dos instalaciones distintas generan ids distintos', () async {
      final a = await idClienteActualizaciones();
      SharedPreferences.setMockInitialValues({});
      final b = await idClienteActualizaciones();
      expect(a, isNot(b));
    });
  });

  group('ServicioActualizaciones', () {
    late ValueNotifier<bool> ventaAbierta;
    late DateTime ahora;
    late List<String> urlsPedidas;

    ServicioActualizaciones crear({
      required http.Client cliente,
      String version = '1.0.0.2098',
    }) => ServicioActualizaciones(
      cliente: cliente,
      versionActual: () async => version,
      ventaAbierta: ventaAbierta,
      reloj: () => ahora,
      abrirInstalador: (_) async {},
    );

    setUp(() {
      ventaAbierta = ValueNotifier(false);
      ahora = DateTime(2026, 9, 30, 12);
      urlsPedidas = [];
    });

    MockClient cliente(String Function() cuerpo, {int status = 200}) =>
        MockClient((req) async {
          urlsPedidas.add(req.url.toString());
          return http.Response(cuerpo(), status);
        });

    test('pide el feed con el cid persistente', () async {
      final s = crear(cliente: cliente(() => _feed('1.0.0.2099')));
      await s.revisar();
      final cid = await idClienteActualizaciones();
      expect(urlsPedidas.single, contains('cid=$cid'));
      expect(urlsPedidas.single, contains('platform=windows'));
    });

    test('feed mayor: queda la versión disponible y se avisa', () async {
      final s = crear(cliente: cliente(() => _feed('1.0.0.2099')));
      await s.revisar();
      expect(s.versionDisponible, '1.0.0.2099');
      expect(s.mostrarAviso, isTrue);
    });

    test('mismo build o menor: al día, sin aviso', () async {
      for (final v in ['1.0.0.2098', '1.0.0.2097']) {
        final s = crear(cliente: cliente(() => _feed(v)));
        await s.revisar();
        expect(s.versionDisponible, isNull, reason: v);
        expect(s.mostrarAviso, isFalse, reason: v);
      }
    });

    test('con venta abierta no avisa, y avisa apenas se cierra', () async {
      ventaAbierta.value = true;
      final s = crear(cliente: cliente(() => _feed('1.0.0.2099')));
      await s.revisar();
      expect(s.mostrarAviso, isFalse);

      var notificaciones = 0;
      s.addListener(() => notificaciones++);
      ventaAbierta.value = false;
      expect(s.mostrarAviso, isTrue);
      expect(notificaciones, greaterThan(0), reason: 'la UI tiene que enterarse');
    });

    test('"más tarde" silencia y vuelve a avisar pasada la postergación', () async {
      final s = crear(cliente: cliente(() => _feed('1.0.0.2099')));
      await s.revisar();
      s.postergar();
      expect(s.mostrarAviso, isFalse);
      ahora = ahora.add(postergacionAviso);
      expect(s.mostrarAviso, isTrue);
    });

    test('sin internet falla en silencio', () async {
      final s = crear(
        cliente: MockClient((_) async => throw const SocketException('sin red')),
      );
      await expectLater(s.revisar(), completes);
      expect(s.versionDisponible, isNull);
      expect(s.mostrarAviso, isFalse);
    });

    test('un error del servidor o un feed roto no cuenta como actualización', () async {
      final s500 = crear(cliente: cliente(() => 'Internal error', status: 500));
      await s500.revisar();
      expect(s500.versionDisponible, isNull);

      final sBasura = crear(cliente: cliente(() => '<html>502</html>'));
      await sBasura.revisar();
      expect(sBasura.versionDisponible, isNull);
    });

    test('un timeout de red falla en silencio', () async {
      final s = crear(
        cliente: MockClient((_) => Completer<http.Response>().future),
      );
      s.tiempoLimite = const Duration(milliseconds: 20);
      await expectLater(s.revisar(), completes);
      expect(s.versionDisponible, isNull);
    });

    test('una falla posterior no borra la actualización ya detectada', () async {
      var falla = false;
      final s = crear(
        cliente: MockClient((_) async {
          if (falla) throw const SocketException('sin red');
          return http.Response(_feed('1.0.0.2099'), 200);
        }),
      );
      await s.revisar();
      falla = true;
      await s.revisar();
      expect(s.versionDisponible, '1.0.0.2099');
    });

    test('instalarAhora abre el instalador con la URL del feed', () async {
      String? abierta;
      final s = ServicioActualizaciones(
        cliente: cliente(() => _feed('1.0.0.2099')),
        versionActual: () async => '1.0.0.2098',
        ventaAbierta: ventaAbierta,
        reloj: () => ahora,
        abrirInstalador: (url) async => abierta = url,
      );
      await s.instalarAhora();
      expect(abierta, contains('horsepos.com/api/update/appcast.xml'));
      expect(abierta, contains('cid='));
    });
  });
}
