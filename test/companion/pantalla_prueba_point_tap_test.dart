// La prueba de Point Tap (`pantalla_prueba_point_tap.dart`): muestra si está la app de Mercado Pago, manda el cobro con el monto
// y la tarjeta elegida, y deja a la vista la respuesta cruda.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/pantalla_prueba_point_tap.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

void main() {
  const canal = MethodChannel('nodosur/point_tap');
  final llamadas = <MethodCall>[];

  setUp(() {
    llamadas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
      llamadas.add(c);
      return switch (c.method) {
        'disponible' => {'app': true, 'accion': true, 'actividad': 'com.mercadopago.wallet/.Point'},
        'cobrar' => {'resultCode': 'OK', 'result_status': 'OK', 'payment_id': '123456'},
        _ => null,
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

  testWidgets('pregunta si está Mercado Pago, cobra con débito el monto escrito y muestra lo que contesta', (t) async {
    t.view.physicalSize = const Size(430, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: const PantallaPruebaPointTap()));
    await t.pumpAndSettle();
    expect(find.textContaining('app: true'), findsOneWidget);

    await t.enterText(find.byType(TextField), '250');
    await t.tap(find.text('Cobrar con débito'));
    await t.pumpAndSettle();
    final cobro = llamadas.firstWhere((c) => c.method == 'cobrar');
    expect((cobro.arguments as Map)['monto'], 250);
    expect((cobro.arguments as Map)['tipo'], 'debit_card');
    expect(find.textContaining('payment_id: 123456'), findsOneWidget);
  });
}
