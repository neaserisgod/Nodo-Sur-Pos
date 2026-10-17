// Los pedidos del bot en la lista de un local gastronómico (`SincronizadorPedidosBot`, `REGLAS-NEGOCIO.md` §22): bajan una sola
// vez y entran "por confirmar" (o solos, si el local quiere), lo que el local hace con cada uno le llega al bot en orden, y cómo
// trabaja el local (entregas, zonas, cocina, horario) llega a la configuración del bot.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/pedidos_bot_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late String gidMila;
  late List<Map<String, dynamic>> remotos;
  late List<Map<String, dynamic>> avisos;
  late Map<String, dynamic>? configSitio;
  late SincronizadorPedidosBot sinc;
  var avisosDePantalla = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
    final usuario = (await db.select(db.usuarios).get()).first.id;
    await configurarRubro(db, PlantillaRubro.rotiseria);
    final mila = await crearProducto(db, nombre: 'Milanesa con papas', precioCentavos: 650000, usuarioId: usuario);
    gidMila = (await (db.select(db.productos)..where((p) => p.id.equals(mila))).getSingle()).globalId!;
    remotos = [];
    avisos = [];
    configSitio = {'numero_actual': '5492944111111', 'numero_duena': '5492944222222'};
    final cliente = ClienteNube(http: MockClient((r) async {
      switch (r.url.path) {
        case '/api/bot/estado':
          return http.Response(jsonEncode({'tieneBot': true, 'puedeConfigurar': true}), 200);
        case '/api/bot/config':
          if (r.method == 'POST') {
            configSitio = (jsonDecode(r.body) as Map<String, dynamic>)['config'] as Map<String, dynamic>;
            return http.Response(jsonEncode({'ok': true, 'version': 2}), 200);
          }
          return http.Response(jsonEncode({'version': 1, 'config': configSitio}), 200);
        case '/api/bot/pedidos':
          final desde = int.parse(r.url.queryParameters['desde']!);
          final lista = [for (final p in remotos) if ((p['actualizado'] as int) > desde) p];
          return http.Response(jsonEncode({'pedidos': lista, 'hasta': lista.isEmpty ? desde : lista.last['actualizado'], 'mas': false}), 200);
        case '/api/bot/pedido/resolver':
        case '/api/bot/pedido/estado':
          avisos.add({'ruta': r.url.path.split('/').last, ...jsonDecode(r.body) as Map<String, dynamic>});
          return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('{}', 404);
    }));
    avisosDePantalla = 0;
    sinc = SincronizadorPedidosBot(db: db, cliente: cliente, alBajar: () => avisosDePantalla++);
  });
  tearDown(() {
    pedidosBotSinCargar.value = const [];
    sinc.cerrar();
    return db.close();
  });

  Map<String, dynamic> pedido(int id, {String? gid, Map<String, dynamic>? entrega, String? pago}) => {
        'id': id,
        'pedidoId': 'pedido-$id',
        'estado': 'por_confirmar',
        'cliente': {'nombre': 'Caro', 'telefono': '5492944333333'},
        'items': [
          {'gid': gid ?? gidMila, 'nombre': 'Milanesa con papas', 'cantidad': 2, 'precioCentavos': 650000},
        ],
        'entrega': ?entrega,
        'pago': ?pago,
        'creado': 1760600000000,
        'actualizado': id,
      };

  test('baja una sola vez, entra por confirmar y avisa a la pantalla', () async {
    remotos.add(pedido(1));
    await sinc.vuelta('t');
    await sinc.vuelta('t');
    final lista = await pedidosAbiertos(db);
    expect(lista, hasLength(1));
    expect(lista.single.idRemoto, '1');
    expect(EstadoPedido.desdeClave(lista.single.estado), EstadoPedido.porConfirmar);
    expect(lista.single.telefono, '5492944333333');
    expect(avisosDePantalla, 1);
    expect(avisos, isEmpty, reason: 'nada que avisar mientras nadie lo toca');
  });

  test('con envío trae la dirección, la zona y su costo tal cual los dijo el bot', () async {
    remotos.add(pedido(2, entrega: {'forma': 'CADETE', 'direccion': 'Mitre 100', 'zona': 'Centro', 'costoEnvioCentavos': 150000}, pago: 'mp'));
    await sinc.vuelta('t');
    final p = (await pedidosAbiertos(db)).single;
    expect(FormaEntrega.desdeClave(p.formaEntrega), FormaEntrega.cadetePropio);
    expect(p.zona, 'Centro');
    expect(p.costoEnvioCentavos, 150000);
    expect(p.pagado, isTrue, reason: 'por Mercado Pago el bot lo manda con el pago acreditado');
  });

  test('lo que el local hace le llega al bot en orden: aceptar, listo y entregado', () async {
    remotos.add(pedido(3));
    await sinc.vuelta('t');
    final id = (await pedidosAbiertos(db)).single.id;
    // Se acepta y se pone listo antes de la próxima vuelta: el sitio primero tiene que enterarse de que se aceptó.
    await avanzarPedido(db, id, EstadoPedido.porHacer);
    await avanzarPedido(db, id, EstadoPedido.listo);
    await sinc.vuelta('t');
    await avanzarPedido(db, id, EstadoPedido.entregado);
    await sinc.vuelta('t');
    await sinc.vuelta('t');
    expect(avisos, [
      {'ruta': 'resolver', 'id': 3, 'estado': 'aceptado'},
      {'ruta': 'estado', 'id': 3, 'estado': 'listo'},
      {'ruta': 'estado', 'id': 3, 'estado': 'entregado'},
    ]);
  });

  test('con "entran solos" se acepta en la misma vuelta', () async {
    await guardarConfigPedidos(db, const ConfigPedidos(confirmacionAutomatica: true));
    remotos.add(pedido(4));
    await sinc.vuelta('t');
    expect(EstadoPedido.desdeClave((await pedidosAbiertos(db)).single.estado), EstadoPedido.porHacer);
    expect(avisos, [{'ruta': 'resolver', 'id': 4, 'estado': 'aceptado'}]);
  });

  test('uno con un plato que no está acá no entra: se dice por qué y se reintenta', () async {
    remotos.add(pedido(5, gid: 'plato-que-no-esta'));
    await sinc.vuelta('t');
    expect(await pedidosAbiertos(db), isEmpty);
    expect(pedidosBotSinCargar.value.single, contains('no está en la carta'));
    // Llega el plato (por la sync, por ejemplo) y en la próxima vuelta entra.
    remotos.first['items'] = [
      {'gid': gidMila, 'nombre': 'Milanesa con papas', 'cantidad': 1, 'precioCentavos': 650000},
    ];
    await sinc.vuelta('t');
    expect(await pedidosAbiertos(db), hasLength(1));
    expect(pedidosBotSinCargar.value, isEmpty);
  });

  test('cómo trabaja el local llega a la configuración del bot, y cambiar la cocina también', () async {
    await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [ZonaEnvio(nombre: 'Centro', costoCentavos: 150000, demoraExtraMin: 15)]));
    await sinc.vuelta('t');
    final p = configSitio!['pedidos'] as Map;
    expect(p['cadete'], isTrue);
    expect(p['zonas'], [
      {'nombre': 'Centro', 'costo': 1500, 'demora_min': 15},
    ]);
    expect(p['cocina'], 'normal');
    expect(p['catalogo_whatsapp'], isFalse);
    expect(configSitio!['numero_actual'], '5492944111111', reason: 'lo demás de la configuración queda');
    expect(configSitio!['horarios'], isA<Map>());

    await cambiarEstadoCocina(db, EstadoCocina.pausada);
    await sinc.vuelta('t');
    expect((configSitio!['pedidos'] as Map)['cocina'], 'pausada');
  });

  test('un almacén no toca nada', () async {
    await configurarRubro(db, PlantillaRubro.almacen);
    remotos.add(pedido(6));
    await sinc.vuelta('t');
    expect(await pedidosAbiertos(db), isEmpty);
    expect(configSitio!.containsKey('pedidos'), isFalse);
  });
}
