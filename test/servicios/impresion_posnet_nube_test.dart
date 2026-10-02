// Imprimir por el servidor de Nodo Sur (2026-10-02): directo con el token local como siempre, o por el servidor cuando se pide
// (interruptor de prueba) o cuando el equipo no tiene token.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/cobro_posnet.dart';
import 'package:la_plazoleta/data/impresion_posnet.dart';
import 'package:la_plazoleta/domain/ticket.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/impresion_posnet_nube.dart';
import 'package:la_plazoleta/servicios/pasarela_point_nube.dart';
import 'package:la_plazoleta/servicios/preferencia_cobro_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

Future<AlmacenCuentaEnMemoria> _conCuenta() async {
  final a = AlmacenCuentaEnMemoria();
  await a.guardar(const CuentaVinculada(token: 'tok-dispositivo', email: 'a@b.com', idDispositivo: 'd', nombreDispositivo: 'Cel', vence: 99));
  return a;
}

void main() {
  final ticket = construirTicket(
    fecha: DateTime(2026, 8, 30, 15, 0),
    vendedor: 'Dueño',
    lineas: const [LineaTicket(nombreProducto: 'Coca-Cola 500ml', cantidad: 2, subtotalCentavos: 224000)],
    desglose: const DesgloseTicket(),
  );

  test('con token y terminal cargados imprime directo contra Mercado Pago, sin tocar el servidor', () async {
    final hosts = <String>[];
    final directo = MockClient((r) async {
      hosts.add(r.url.host);
      return http.Response('{}', 200);
    });
    await imprimirTicketPosnet(
      ticket: ticket, encabezadoNegocio: 'x', accessToken: 'APP_USR-x', terminalId: 'N950', client: directo,
      almacen: await _conCuenta(), cliente: ClienteNube(http: MockClient((r) async => fail('no tenía que llamar al sitio'))),
    );
    expect(hosts, ['api.mercadopago.com']);
  });

  test('con el interruptor, aunque haya token, imprime por el servidor con el contenido del ticket', () async {
    late Map<String, dynamic> cuerpo;
    final nube = ClienteNube(http: MockClient((r) async {
      expect(r.url.path, '/api/mp/imprimir');
      expect(r.headers['Authorization'], 'Bearer tok-dispositivo');
      cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
      return _json({'ok': true});
    }));
    await imprimirTicketPosnet(
      ticket: ticket, encabezadoNegocio: 'La Plazoleta', accessToken: 'APP_USR-x', terminalId: 'N950', forzarNube: true,
      almacen: await _conCuenta(), cliente: nube, client: MockClient((r) async => fail('no tenía que ir directo')),
    );
    expect(cuerpo['contenido'], contenidoTicketPosnetMp(ticket, encabezadoNegocio: 'La Plazoleta'));
    expect(cuerpo['externalReference'], startsWith('ticket_'));
    expect((cuerpo['idempotencyKey'] as String).length, 32);
  });

  test('sin token local cae al servidor; sin cuenta dice qué hacer', () async {
    final nube = ClienteNube(http: MockClient((r) async => _json({'ok': true})));
    await imprimirTicketPosnet(ticket: ticket, encabezadoNegocio: 'x', almacen: await _conCuenta(), cliente: nube);
    await expectLater(
      imprimirTicketPosnet(ticket: ticket, encabezadoNegocio: 'x', almacen: AlmacenCuentaEnMemoria(), cliente: nube),
      throwsA(isA<ImpresionPosnetException>().having((e) => e.mensaje, 'mensaje', contains('horsepos.com/negocio'))),
    );
  });

  test('un rechazo de Mercado Pago llega con código y motivo; un dispositivo desvinculado pide volver a vincular', () async {
    final rechazo = ClienteNube(http: MockClient((r) async => _json({'error': 'mp_rechazo', 'status': 400, 'mensaje': 'property_value · terminal_id does not match pattern'}, 502)));
    await expectLater(
      imprimirTicketPosnet(ticket: ticket, encabezadoNegocio: 'x', forzarNube: true, almacen: await _conCuenta(), cliente: rechazo),
      throwsA(isA<ImpresionPosnetException>().having((e) => e.mensaje, 'mensaje', allOf(contains('property_value'), contains('Mercado Pago respondió')))),
    );
    final caido = ClienteNube(http: MockClient((r) async => _json({'error': 'no_device'}, 401)));
    await expectLater(
      imprimirTicketPosnet(ticket: ticket, encabezadoNegocio: 'x', forzarNube: true, almacen: await _conCuenta(), cliente: caido),
      throwsA(isA<ImpresionPosnetException>().having((e) => e.mensaje, 'mensaje', contains('ya no está vinculado'))),
    );
  });

  test('el cobro también respeta el interruptor: con token y terminal cargados, forzarNube va por el servidor', () async {
    final nube = ClienteNube(http: MockClient((r) async => _json({'connected': true, 'needsReconnect': false, 'terminalConfigured': true})));
    final p = await elegirPasarelaPoint(accessToken: 'APP_USR-x', terminalId: 'T1', forzarNube: true, almacen: await _conCuenta(), cliente: nube);
    expect(p, isA<PasarelaPointNube>());
    final q = await elegirPasarelaPoint(accessToken: 'APP_USR-x', terminalId: 'T1', almacen: await _conCuenta(), cliente: nube);
    expect(q, isA<PasarelaPointDirecta>());
  });

  test('el interruptor arranca apagado, se guarda y es de este equipo', () async {
    SharedPreferences.setMockInitialValues({});
    await PreferenciaCobroNube.cargar();
    expect(PreferenciaCobroNube.activo, isFalse);
    await PreferenciaCobroNube.guardar(true);
    SharedPreferences.setMockInitialValues({'cobro_por_nodo_sur': true}); // otra "sesión": se lee de lo guardado
    await PreferenciaCobroNube.guardar(false);
    await PreferenciaCobroNube.cargar();
    expect(PreferenciaCobroNube.activo, isFalse);
    SharedPreferences.setMockInitialValues({'cobro_por_nodo_sur': true});
    await PreferenciaCobroNube.cargar();
    expect(PreferenciaCobroNube.activo, isTrue);
    await PreferenciaCobroNube.guardar(false);
  });
}
