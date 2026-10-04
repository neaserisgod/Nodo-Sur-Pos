// Etapa A (2026-10-04): por la conexión en vivo de la sync llegan también los avisos de Mercado Pago sobre una orden de
// cobro. No son "bajá datos": van al diálogo de cobro, que consulta la orden al instante.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/avisos_cobro_mp.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

void main() {
  test('un aviso de orden va a los avisos de Mercado Pago y no dispara una bajada; los demás mensajes sí', () async {
    final socket = StreamController<dynamic>();
    final cliente = ClienteNube(
      http: MockClient((_) async => http.Response('{}', 200)),
      abrirEscucha: (uri, cabeceras) async => socket.stream,
    );
    final bajadas = <void>[];
    final ordenes = <String>[];
    final subAvisos = avisosOrdenMp.listen(ordenes.add);
    final sub = (await cliente.escuchar('token')).listen(bajadas.add);

    socket.add('{"seq":12}');
    socket.add('{"mp":{"orden":"ORD123","accion":"processed"}}');
    socket.add('{"mp":"roto"}');
    socket.add('no es json');
    await Future<void>.delayed(Duration.zero);

    expect(ordenes, ['ORD123']);
    expect(bajadas.length, 3, reason: 'el seq, y ante la duda (mensajes que no se entienden) se sincroniza de más');
    await sub.cancel();
    await subAvisos.cancel();
    await socket.close();
  });

  test('esperarAvisoOrden vuelve con el aviso de SU orden, o al cumplirse el tiempo', () async {
    final reloj = Stopwatch()..start();
    final espera = esperarAvisoOrden('ORD1', const Duration(seconds: 5));
    avisarOrdenMp('OTRA');
    avisarOrdenMp('ORD1');
    await espera;
    expect(reloj.elapsed < const Duration(seconds: 1), isTrue);

    final sinAviso = Stopwatch()..start();
    await esperarAvisoOrden('ORD2', const Duration(milliseconds: 50));
    expect(sinAviso.elapsed >= const Duration(milliseconds: 50), isTrue);
  });
}
