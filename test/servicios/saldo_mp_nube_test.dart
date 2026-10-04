// Etapa E (2026-10-04): pedir el saldo real a Mercado Pago por el sitio y esperar el reporte sin frenar el cierre.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/saldo_mp_nube.dart';

const _cuenta = CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-1', nombreDispositivo: 'Caja', vence: 99);

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json'});

final _listo = {
  'estado': 'listo',
  'saldoDisponibleCentavos': 6000000,
  'aLiberarCentavos': 244000,
  'hasta': 1790874000,
  'truncado': false,
  'movimientos': [
    {'fecha': 1790860000, 'tipo': 'release', 'descripcion': 'payout', 'creditoCentavos': 0, 'debitoCentavos': 4000000, 'referencia': null, 'origen': '55'},
  ],
};

Future<AlmacenCuentaEnMemoria> _conCuenta() async => AlmacenCuentaEnMemoria()..guardar(_cuenta);

void main() {
  test('pide con el momento de apertura, espera mientras está pendiente y devuelve el saldo con su total', () async {
    final pedidos = <String>[];
    var consultas = 0;
    final cliente = ClienteNube(http: MockClient((r) async {
      pedidos.add('${r.method} ${r.url.path}${r.url.query.isEmpty ? '' : '?${r.url.query}'}');
      expect(r.headers['Authorization'], 'Bearer t1');
      if (r.method == 'POST') {
        expect(jsonDecode(r.body), {'desde': DateTime(2026, 10, 4, 8).millisecondsSinceEpoch ~/ 1000});
        return _json({'id': 12});
      }
      return ++consultas < 3 ? _json({'estado': 'pendiente'}) : _json(_listo);
    }));
    final pausas = <Duration>[];
    final traer = traerSaldoMpDeCuenta(await _conCuenta(), cliente, dormir: (d) async => pausas.add(d));

    final saldo = await traer(DateTime(2026, 10, 4, 8));

    expect(pedidos, ['POST /api/mp/saldo', 'GET /api/mp/saldo?id=12', 'GET /api/mp/saldo?id=12', 'GET /api/mp/saldo?id=12']);
    expect(pausas, [esperaEntreConsultasSaldo, esperaEntreConsultasSaldo]);
    expect(saldo.disponibleCentavos, 6000000);
    expect(saldo.totalCentavos, 6244000);
    expect(saldo.contadoSugeridoCentavos, 6244000);
    expect(saldo.movimientos.single.debitoCentavos, 4000000);
    expect(saldo.hasta, DateTime.fromMillisecondsSinceEpoch(1790874000 * 1000));
  });

  test('sin cuenta vinculada avisa qué hacer, sin tocar la red', () async {
    final cliente = ClienteNube(http: MockClient((_) async => throw StateError('no se pide nada')));
    final traer = traerSaldoMpDeCuenta(AlmacenCuentaEnMemoria(), cliente);
    await expectLater(traer(DateTime.now()), throwsA(isA<ErrorNube>().having((e) => e.codigo, 'codigo', 'sin_cuenta')));
  });

  test('si el reporte no llega en el tiempo límite, lo dice; si MP lo da por fallido, también', () async {
    final lento = ClienteNube(http: MockClient((r) async => r.method == 'POST' ? _json({'id': 1}) : _json({'estado': 'pendiente'})));
    final traerLento = traerSaldoMpDeCuenta(await _conCuenta(), lento, limite: const Duration(seconds: 12), dormir: (_) async {});
    await expectLater(traerLento(DateTime.now()), throwsA(isA<ErrorNube>().having((e) => e.codigo, 'codigo', 'mp_demora')));

    final roto = ClienteNube(http: MockClient((r) async => r.method == 'POST' ? _json({'id': 1}) : _json({'estado': 'error', 'motivo': 'mp_reporte_fallo'})));
    final traerRoto = traerSaldoMpDeCuenta(await _conCuenta(), roto, dormir: (_) async {});
    await expectLater(traerRoto(DateTime.now()), throwsA(isA<ErrorNube>().having((e) => e.codigo, 'codigo', 'mp_reporte')));
  });

  test('una consulta suelta que falla no corta la espera; tres seguidas sí; un rechazo del sitio corta de una', () async {
    var consultas = 0;
    final intermitente = ClienteNube(http: MockClient((r) async {
      if (r.method == 'POST') return _json({'id': 1});
      return ++consultas == 2 ? _json({'error': 'mp_error'}, 502) : (consultas < 4 ? _json({'estado': 'pendiente'}) : _json(_listo));
    }));
    final saldo = await traerSaldoMpDeCuenta(await _conCuenta(), intermitente, dormir: (_) async {})(DateTime.now());
    expect(saldo.disponibleCentavos, 6000000);

    var intentos = 0;
    final caido = ClienteNube(http: MockClient((r) async {
      if (r.method == 'POST') return _json({'id': 1});
      intentos++;
      return _json({'error': 'mp_error'}, 502);
    }));
    await expectLater(traerSaldoMpDeCuenta(await _conCuenta(), caido, dormir: (_) async {})(DateTime.now()), throwsA(isA<ErrorNube>()));
    expect(intentos, 3, reason: 'tres consultas seguidas fallidas cortan la espera');

    final sinPermiso = ClienteNube(http: MockClient((r) async => r.method == 'POST' ? _json({'error': 'forbidden'}, 403) : _json({})));
    await expectLater(traerSaldoMpDeCuenta(await _conCuenta(), sinPermiso, dormir: (_) async {})(DateTime.now()), throwsA(isA<ErrorNube>()));
  });
}
