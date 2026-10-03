// Conectar el celular con la PC: solo por la cuenta, o buscándola en el wifi y con el código de 6 números.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/pantalla_emparejamiento.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

void main() {
  Future<List<DatosConexion>> montar(
    WidgetTester t, {
    DatosConexion? deLaCuenta,
    String? enElWifi,
    Future<DatosConexion> Function(String ip, int puerto, String codigo)? canjear,
  }) async {
    final conectados = <DatosConexion>[];
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaEmparejamiento(
        pcDeLaCuenta: () async => deLaCuenta,
        buscarEnElWifi: () async => enElWifi,
        probar: (_, _) async => true,
        canjear: canjear ?? (ip, puerto, codigo) async => DatosConexion(ip: ip, puerto: puerto, token: 'llave-$codigo'),
        alConectar: (d) async => conectados.add(d),
      ),
    ));
    // Sin `pumpAndSettle`: mientras busca hay una ruedita que no termina nunca.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return conectados;
  }

  testWidgets('con la cuenta y la PC de la sucursal avisada, se conecta solo, sin código', (t) async {
    final c = await montar(t, deLaCuenta: const DatosConexion(ip: '192.168.0.23', puerto: 8099, token: 'llave'));
    expect(c.single.ip, '192.168.0.23');
    expect(find.byKey(const Key('emparejar_codigo')), findsNothing);
  });

  testWidgets('sin cuenta: encuentra la PC en el wifi y pide el código', (t) async {
    final c = await montar(t, enElWifi: '192.168.0.23');
    expect(find.text('PC encontrada en 192.168.0.23'), findsOneWidget);
    await t.enterText(find.byKey(const Key('emparejar_codigo')), '482913');
    await t.tap(find.byKey(const Key('emparejar_conectar')));
    await t.pumpAndSettle();
    expect(c.single.token, 'llave-482913');
  });

  testWidgets('un código que la PC rechaza muestra el motivo y deja reintentar', (t) async {
    final c = await montar(t, enElWifi: '192.168.0.23', canjear: (_, _, _) async => throw const ErrorCompanion(401, 'Código incorrecto. Revisalo en la PC y probá de nuevo.'));
    await t.enterText(find.byKey(const Key('emparejar_codigo')), '000000');
    await t.tap(find.byKey(const Key('emparejar_conectar')));
    await t.pumpAndSettle();
    expect(find.textContaining('Código incorrecto'), findsOneWidget);
    expect(c, isEmpty);
  });

  testWidgets('si no encuentra la PC ofrece buscar de nuevo o escribir la dirección', (t) async {
    final c = await montar(t);
    expect(find.text('No encontramos la PC'), findsOneWidget);
    await t.tap(find.text('Escribir la dirección a mano'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('emparejar_ip')), '10.0.0.7');
    await t.enterText(find.byKey(const Key('emparejar_codigo')), '123456');
    await t.tap(find.byKey(const Key('emparejar_conectar')));
    await t.pumpAndSettle();
    expect(c.single.ip, '10.0.0.7');
  });
}
