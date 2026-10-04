// Etapa D (2026-10-04): los avisos de cobros, contracargos y reclamos llegan en vivo o al arrancar, se guardan una sola vez y
// la campanita muestra solo lo que no tiene venta.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/domain/avisos_mp.dart';
import 'package:la_plazoleta/servicios/avisos_cobro_mp.dart';
import 'package:la_plazoleta/servicios/avisos_mp_servicio.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import '../helpers/base_para_tests.dart';

const _cuenta = CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-1', nombreDispositivo: 'Caja', vence: 99);

Map<String, dynamic> _json(int id, {String tipo = 'cobro', String mpId = '9', int? monto = 5000, int minutos = 30}) {
  final seg = DateTime.now().subtract(Duration(minutes: minutos)).millisecondsSinceEpoch ~/ 1000;
  return {'id': id, 'tipo': tipo, 'mpId': mpId, 'pagoId': '9', 'montoCentavos': monto, 'referencia': null, 'estado': 'approved', 'detalle': null, 'fecha': seg, 'creado': seg};
}

void main() {
  test('al arrancar baja lo que falta desde el último id y lo deja en la campanita; un segundo pedido no duplica', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final almacen = AlmacenCuentaEnMemoria();
    await almacen.guardar(_cuenta);
    final pedidos = <String>[];
    final cliente = ClienteNube(http: MockClient((r) async {
      pedidos.add('${r.url.path}?${r.url.query}');
      expect(r.headers['Authorization'], 'Bearer t1');
      return http.Response(jsonEncode({'avisos': [_json(1, monto: 5000), _json(2, tipo: 'contracargo', mpId: 'CB1', monto: 9000)]}), 200);
    }));
    final s = ServicioAvisosMp(db: db, almacen: almacen, cliente: cliente);

    await s.bajarPendientes();
    expect(pedidos.single, '/api/mp/avisos?desde=0');
    expect(s.pendientes.value.map((a) => a.tipo).toSet(), {TipoAvisoMp.cobro, TipoAvisoMp.contracargo});

    await s.bajarPendientes();
    expect(pedidos.last, '/api/mp/avisos?desde=2', reason: 'pide desde el último que ya tiene');
    expect(s.pendientes.value, hasLength(2), reason: 'no duplica');
  });

  test('un aviso en vivo se guarda; "visto" lo saca; sin cuenta o sin red no rompe nada', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final almacen = AlmacenCuentaEnMemoria(); // sin cuenta
    final cliente = ClienteNube(http: MockClient((_) async => throw StateError('sin cuenta no se pide nada')));
    final s = ServicioAvisosMp(db: db, almacen: almacen, cliente: cliente, repaso: const Duration(hours: 1));
    s.iniciar();
    addTearDown(s.detener);
    await Future<void>.delayed(Duration.zero);
    expect(s.pendientes.value, isEmpty);

    final aviso = avisoMpDesdeJson(_json(7, tipo: 'reclamo', mpId: 'CL1', monto: 7000))!;
    avisarAvisoMp(aviso);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.pendientes.value.single.titulo, contains('Reclamo'));

    await s.marcarVisto(s.pendientes.value.single.aviso);
    expect(s.pendientes.value, isEmpty);

    await almacen.guardar(_cuenta);
    final sinRed = ClienteNube(http: MockClient((_) async => throw const SocketLikeError()));
    final s2 = ServicioAvisosMp(db: db, almacen: almacen, cliente: sinRed);
    await s2.bajarPendientes(); // no tira
  });

  test('un cobro recién entrado no avisa todavía: la venta se está grabando', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final almacen = AlmacenCuentaEnMemoria();
    final cliente = ClienteNube(http: MockClient((_) async => http.Response('{}', 404)));
    final s = ServicioAvisosMp(db: db, almacen: almacen, cliente: cliente);
    avisarAvisoMp(avisoMpDesdeJson(_json(1, minutos: 1))!);
    s.iniciar();
    addTearDown(s.detener);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.pendientes.value, isEmpty, reason: 'recién entró: la venta todavía se está grabando');
  });

  test('avisoMpDesdeJson: lee lo del sitio y descarta lo que no entiende', () {
    final a = avisoMpDesdeJson(_json(3, tipo: 'contracargo', mpId: 'CB9', monto: 1234))!;
    expect((a.idServidor, a.tipo, a.mpId, a.montoCentavos), (3, TipoAvisoMp.contracargo, 'CB9', 1234));
    expect(avisoMpDesdeJson({'id': 1, 'tipo': 'algo-nuevo', 'mpId': 'x'}), isNull, reason: 'un tipo de un sitio más nuevo');
    expect(avisoMpDesdeJson({'tipo': 'cobro'}), isNull);
  });

  test('por la conexión en vivo: el aviso va a los avisos de MP sin disparar una bajada, y abrir la conexión lo avisa', () async {
    final socket = StreamController<dynamic>();
    final cliente = ClienteNube(http: MockClient((_) async => http.Response('{}', 200)), abrirEscucha: (uri, cabeceras) async => socket.stream);
    final recibidos = <AvisoMp>[];
    var aperturas = 0;
    final sub1 = avisosMpEnVivo.listen(recibidos.add);
    final sub2 = conexionEnVivoAbierta.listen((_) => aperturas++);
    final bajadas = <void>[];
    final sub = (await cliente.escuchar('token')).listen(bajadas.add);

    socket.add(jsonEncode({'mp': {'aviso': _json(5, monto: 100)}}));
    socket.add(jsonEncode({'mp': {'aviso': {'id': 6, 'tipo': 'nuevo-tipo', 'mpId': 'x'}}}));
    await Future<void>.delayed(Duration.zero);

    expect(recibidos.map((a) => a.idServidor), [5]);
    expect(bajadas, isEmpty, reason: 'un aviso de Mercado Pago, entendido o no, no es "bajá datos"');
    expect(aperturas, 1);
    await sub.cancel();
    await sub1.cancel();
    await sub2.cancel();
    await socket.close();
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
