import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/companion/pantalla_cargar_factura.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:la_plazoleta/servicios/flujo_factura.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

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

const _factura =
    '{"facturas":[{"proveedor":{"razon_social":"Distribuidora ELPAR srl","cuit":"30-70817475-7"},"tipo":"A","numero":"0011-00266439",'
    '"fecha":"2026-07-24","condicion_pago":"cuenta_corriente","lineas":[{"codigo":"1042","descripcion":"1042 - CREMA SIMPLE X 200 GR (24)","cantidad":4,'
    '"precio_unitario":1908.26,"descuento_pct":5,"importe":7251.41}],"pie":{"total":8774.21}}]}';

/// Cargar factura en el celular (El dueño, 2026-10-07): el mismo flujo de la PC, contra la base del celular.
void main() {
  late AppDatabase db;
  late int elpar;
  late int crema;
  late int usuario;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest('AIza-buena');
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    elpar = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'EL', nombre: 'Distribuidora Elpar'));
    crema = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Crema 200', proveedorId: Value(elpar), precioCentavos: const Value(300000), costoCentavos: const Value(200000), stock: const Value(3)),
        );
    // Ya se cargó antes una factura de Elpar en la PC: el CUIT y el vínculo llegaron por la sync.
    await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
    await aprenderVinculo(db, proveedorId: elpar, productoId: crema, codigo: '1042', descripcion: '1042 - CREMA SIMPLE X 200 GR (24)');
  });
  tearDown(() => db.close());

  Future<FlujoFactura> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final flujo = FlujoFactura(
      db: db,
      clienteIa: MockClient((_) async => http.Response(_respuesta(_factura), 200)),
      adjuntosIniciales: [AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3]))],
    );
    addTearDown(flujo.dispose);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaCargarFactura(db: db, usuarioId: usuario, flujo: flujo)));
    await tester.pumpAndSettle();
    return flujo;
  }

  testWidgets('lee la foto, reconoce al proveedor por el CUIT y la línea por lo aprendido, y aplica stock, costo y deuda', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('Leer con IA'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Distribuidora Elpar'), findsOneWidget);
    expect(find.text('Cierra con el total impreso'), findsOneWidget);
    expect(find.text('Crema 200'), findsOneWidget, reason: 'vinculada sola por lo aprendido');
    expect(find.textContaining('2.194'), findsOneWidget, reason: 'costo por unidad con IVA');

    await tester.ensureVisible(find.text('Aplicar factura'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar factura'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Deshacer factura'), findsOneWidget);
    expect(await saldoDeuda(db, elpar), 877421);
    final p = await (db.select(db.productos)..where((t) => t.id.equals(crema))).getSingle();
    expect(p.stock, 7);
    expect(p.costoCentavos, 219400);
    await tester.pump(const Duration(seconds: 6)); // el aviso "Factura aplicada" se va solo
  });

  testWidgets('sin clave de la IA avisa dónde cargarla y no deja leer', (tester) async {
    ClaveGemini.fijarParaTest(null);
    await abrir(tester);
    expect(find.textContaining('Asistente IA'), findsOneWidget);
    await tester.tap(find.text('Leer con IA'));
    await tester.pumpAndSettle();
    expect(find.text('Cierra con el total impreso'), findsNothing);
  });
}
