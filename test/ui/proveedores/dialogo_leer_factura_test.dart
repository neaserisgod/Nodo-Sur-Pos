import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/ui/proveedores/dialogo_leer_factura.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _respuesta(String json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': json},
            ],
          },
        },
      ],
    });

String _factura(String total) =>
    '{"facturas":[{"proveedor":{"razon_social":"Distribuidora ELPAR srl","cuit":"30-70817475-7"},"tipo":"A","numero":"0011-00266439",'
    '"fecha":"2026-07-24","condicion_pago":"cuenta_corriente","lineas":[{"descripcion":"1042 - CREMA SIMPLE X 200 GR (24)","cantidad":4,'
    '"precio_unitario":1908.26,"descuento_pct":5,"importe":7251.41}],"pie":{"total":$total}}]}';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest('AIza-buena');
  });

  Future<void> abrir(WidgetTester tester, http.Client ia) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarDialogoLeerFactura(context, clienteIa: ia, adjuntosIniciales: [AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3]))]),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('lee, muestra el costo de cada producto y avisa que cierra con el total', (tester) async {
    await abrir(tester, MockClient((_) async => http.Response(_respuesta(_factura('8774.21')), 200)));
    await tester.tap(find.text('Leer con IA'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Distribuidora ELPAR srl'), findsOneWidget);
    expect(find.text('Cierra con el total impreso'), findsOneWidget);
    expect(find.textContaining('importes sin IVA'), findsOneWidget);
    // 4 unidades, neto 7.251,41 + IVA 1.522,80 = 8.774,21 → 2.193,55 → $2.194 c/u.
    expect(find.textContaining('2.194'), findsOneWidget);
    expect(find.text('Copiar lectura'), findsOneWidget);
  });

  testWidgets('si la factura no cierra, lo dice y marca la diferencia', (tester) async {
    await abrir(tester, MockClient((_) async => http.Response(_respuesta(_factura('9774.21')), 200)));
    await tester.tap(find.text('Leer con IA'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No cierra: diferencia de'), findsOneWidget);
    expect(find.text('Cierra con el total impreso'), findsNothing);
  });

  testWidgets('un fallo de la IA se muestra legible y no rompe la pantalla', (tester) async {
    await abrir(tester, MockClient((_) async => http.Response('{}', 429)));
    await tester.tap(find.text('Leer con IA'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cupo gratis'), findsOneWidget);
  });

  testWidgets('sin clave no deja leer y explica dónde cargarla', (tester) async {
    ClaveGemini.fijarParaTest(null);
    await abrir(tester, MockClient((_) async => fail('no tenía que llamar a Google')));
    expect(find.textContaining('Configuración › Asistente IA'), findsOneWidget);
    final boton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Leer con IA'));
    expect(boton.onPressed, isNull);
  });
}
