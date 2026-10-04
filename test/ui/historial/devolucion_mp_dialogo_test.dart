// Etapa B: después de anular, la pregunta "¿Devolver por Mercado Pago?" y el resultado.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/devolucion_mp.dart';
import 'package:la_plazoleta/ui/historial/devolucion_mp_dialogo.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

void main() {
  const cobro = CobroPoint(ordenIdMp: 'ORD-1', externalReference: 'ref-venta-1', montoCentavos: 820000, devuelta: false);

  Future<void> abrir(WidgetTester tester, {required bool canRefund, required List<String> devoluciones}) async {
    final almacen = AlmacenCuentaEnMemoria();
    await almacen.guardar(const CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'pc-1', nombreDispositivo: 'Caja', vence: 1));
    final cliente = ClienteNube(http: MockClient((r) async {
      if (r.url.path == '/api/mp/estado') {
        return http.Response(jsonEncode({'connected': true, 'terminalConfigured': true, 'canRefund': canRefund}), 200);
      }
      devoluciones.add(r.body);
      return http.Response(jsonEncode({'id': 'ORD-1', 'status': 'refunded'}), 200);
    }));
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ofrecerDevolucionDeCobro(context, cobro, almacen: almacen, cliente: cliente),
            child: const Text('Anular'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Anular'));
    await tester.pumpAndSettle();
  }

  testWidgets('pregunta, y con "Sí" devuelve y avisa', (tester) async {
    final devoluciones = <String>[];
    await abrir(tester, canRefund: true, devoluciones: devoluciones);
    expect(find.text('¿Devolver por Mercado Pago?'), findsOneWidget);
    await tester.tap(find.textContaining('Sí, devolver'));
    await tester.pumpAndSettle();
    expect(devoluciones, hasLength(1));
    expect(find.textContaining('se le devolvieron'), findsOneWidget);
  });

  testWidgets('con "No" no devuelve nada', (tester) async {
    final devoluciones = <String>[];
    await abrir(tester, canRefund: true, devoluciones: devoluciones);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(devoluciones, isEmpty);
  });

  testWidgets('a quien no puede devolver (un empleado) ni se le pregunta', (tester) async {
    final devoluciones = <String>[];
    await abrir(tester, canRefund: false, devoluciones: devoluciones);
    expect(find.text('¿Devolver por Mercado Pago?'), findsNothing);
    expect(devoluciones, isEmpty);
  });
}
