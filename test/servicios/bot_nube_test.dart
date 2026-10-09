// El bot de WhatsApp contra el sitio (`ClienteNube`, `/api/bot/*`; `docs/PLAN-BOT.md`): lo que la app pide y manda, y los avisos
// en vivo de pedidos nuevos, que no son "bajá datos".

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/servicios/avisos_bot.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

http.Response _json(Object j, [int estado = 200]) => http.Response(jsonEncode(j), estado, headers: {'content-type': 'application/json'});

void main() {
  test('estado: con el plan trae permisos, versión y bots; sin el plan, tieneBot falso', () async {
    final c = ClienteNube(http: MockClient((r) async {
      expect(r.url.path, '/api/bot/estado');
      expect(r.headers['Authorization'], 'Bearer tok');
      return _json({'tieneBot': true, 'puedeConfigurar': true, 'version': 3, 'bots': [{'nombre': 'Bot', 'ultimaSenal': 1700000000}]});
    }));
    final e = await c.estadoBot('tok');
    expect(e.tieneBot && e.puedeConfigurar, isTrue);
    expect(e.version, 3);
    expect(e.bots.single.ultimaSenal, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    final sin = ClienteNube(http: MockClient((r) async => _json({'tieneBot': false})));
    expect((await sin.estadoBot('tok')).tieneBot, isFalse);
  });

  test('configuración: se baja y se guarda con la forma que espera el sitio', () async {
    Map<String, dynamic>? enviado;
    final c = ClienteNube(http: MockClient((r) async {
      if (r.method == 'GET') return _json({'version': 2, 'config': {'pausa_minutos': 30}, 'actualizada': 1});
      enviado = jsonDecode(r.body) as Map<String, dynamic>;
      return _json({'ok': true, 'version': 3});
    }));
    final leida = await c.configBot('tok');
    expect(leida.version, 2);
    expect(leida.config, {'pausa_minutos': 30});
    expect(await c.guardarConfigBot('tok', {'pausa_minutos': 60}), 3);
    expect(enviado, {'config': {'pausa_minutos': 60}});
  });

  test('catálogo: se publica y dice si cambió', () async {
    Map<String, dynamic>? enviado;
    final c = ClienteNube(http: MockClient((r) async {
      expect(r.url.path, '/api/bot/catalogo');
      enviado = jsonDecode(r.body) as Map<String, dynamic>;
      return _json({'ok': true, 'cambiado': false, 'items': 1});
    }));
    final cambio = await c.publicarCatalogoBot('tok', const [ItemCatalogoBot(gid: 'g', nombre: 'Coca', precioCentavos: 350000, hay: true)]);
    expect(cambio, isFalse);
    expect(enviado, {'items': [{'gid': 'g', 'nombre': 'Coca', 'precioCentavos': 350000, 'hay': true}]});
  });

  test('pedidos: con el cursor; lo que no se entiende se saltea', () async {
    final c = ClienteNube(http: MockClient((r) async {
      expect(r.url.queryParameters['desde'], '55');
      return _json({
        'pedidos': [
          {'id': 1, 'estado': 'por_confirmar', 'cliente': {'nombre': 'Sofi', 'telefono': '549'}, 'items': [{'nombre': 'Yerba', 'cantidad': 2}], 'creado': 1, 'actualizado': 60},
          {'id': 2, 'estado': 'raro'},
        ],
        'hasta': 60,
        'mas': false,
      });
    }));
    final r = await c.pedidosBot('tok', desde: 55);
    expect(r.pedidos.single.clienteNombre, 'Sofi');
    expect(r.hasta, 60);
  });

  test('resolver: acepta o rechaza; si otro equipo ya lo resolvió, lo dice', () async {
    final pedidos = <Map<String, dynamic>>[];
    final c = ClienteNube(http: MockClient((r) async {
      pedidos.add(jsonDecode(r.body) as Map<String, dynamic>);
      return pedidos.length < 3 ? _json({'ok': true}) : _json({'error': 'ya_resuelto', 'estado': 'aceptado'}, 409);
    }));
    await c.resolverPedidoBot('tok', 7, aceptado: true);
    await c.resolverPedidoBot('tok', 8, aceptado: false);
    expect(pedidos, [{'id': 7, 'estado': 'aceptado'}, {'id': 8, 'estado': 'rechazado'}]);
    await expectLater(() => c.resolverPedidoBot('tok', 7, aceptado: false),
        throwsA(isA<ErrorNube>().having((e) => e.codigo, 'codigo', 'ya_resuelto').having((e) => e.mensaje, 'mensaje', contains('otro equipo'))));
  });

  test('un aviso de pedido nuevo despierta a la app y no dispara una bajada de datos', () async {
    final socket = StreamController<dynamic>();
    final cliente = ClienteNube(http: MockClient((_) async => http.Response('{}', 200)), abrirEscucha: (uri, cabeceras) async => socket.stream);
    final bajadas = <void>[];
    final pedidos = <int>[];
    final subPedidos = avisosPedidoBot.listen(pedidos.add);
    final sub = (await cliente.escuchar('token')).listen(bajadas.add);

    socket.add('{"bot":{"pedido":7}}');
    socket.add('{"bot":{}}');
    socket.add('{"seq":3}');
    await Future<void>.delayed(Duration.zero);

    expect(pedidos, [7]);
    expect(bajadas.length, 1, reason: 'solo el seq es "bajá"');
    await sub.cancel();
    await subPedidos.cancel();
    await socket.close();
  });
}
