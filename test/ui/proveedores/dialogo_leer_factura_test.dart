import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/ui/proveedores/dialogo_leer_factura.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/base_para_tests.dart';

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
  late AppDatabase db;
  late int elpar;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest('AIza-buena');
    db = baseDeTest();
    elpar = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'EL', nombre: 'Distribuidora Elpar'));
  });
  tearDown(() => db.close());

  /// El mismo cliente atiende la lectura de la factura y, si hace falta, la consulta de vínculos de la IA.
  http.Client ia({String total = '8774.21', int? vinculaAlProducto, int estadoVinculos = 200}) => MockClient((req) async {
        if (req.body.contains('Productos del comercio')) {
          if (estadoVinculos != 200) return http.Response('{}', estadoVinculos);
          final json = vinculaAlProducto == null ? '{"vinculos":[]}' : '{"vinculos":[{"i":0,"producto_id":$vinculaAlProducto}]}';
          return http.Response(_respuesta(json), 200);
        }
        return http.Response(_respuesta(_factura(total)), 200);
      });

  Future<void> abrir(WidgetTester tester, http.Client cliente) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarDialogoLeerFactura(context, db: db, clienteIa: cliente, adjuntosIniciales: [AdjuntoGemini('image/jpeg', Uint8List.fromList([1, 2, 3]))]),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> leer(WidgetTester tester) async {
    await tester.tap(find.text('Leer con IA'));
    await tester.pumpAndSettle();
  }

  Future<int> producto(String nombre, {int? proveedorId}) =>
      db.into(db.productos).insert(ProductosCompanion.insert(nombre: nombre, proveedorId: Value(proveedorId)));

  group('lectura', () {
    testWidgets('lee, muestra el costo de cada producto y avisa que cierra con el total', (tester) async {
      await abrir(tester, ia());
      await leer(tester);
      expect(find.textContaining('Distribuidora ELPAR srl'), findsOneWidget);
      expect(find.text('Cierra con el total impreso'), findsOneWidget);
      expect(find.textContaining('importes sin IVA'), findsOneWidget);
      // 4 unidades, neto 7.251,41 + IVA 1.522,80 = 8.774,21 → 2.193,55 → $2.194 c/u.
      expect(find.textContaining('2.194'), findsOneWidget);
      expect(find.text('Copiar lectura'), findsOneWidget);
    });

    testWidgets('si la factura no cierra, lo dice y marca la diferencia', (tester) async {
      await abrir(tester, ia(total: '9774.21'));
      await leer(tester);
      expect(find.textContaining('No cierra: diferencia de'), findsOneWidget);
      expect(find.text('Cierra con el total impreso'), findsNothing);
    });

    testWidgets('un fallo de la IA se muestra legible y no rompe la pantalla', (tester) async {
      await abrir(tester, MockClient((_) async => http.Response('{}', 429)));
      await leer(tester);
      expect(find.textContaining('cupo gratis'), findsOneWidget);
    });

    testWidgets('sin clave no deja leer y explica dónde cargarla', (tester) async {
      ClaveGemini.fijarParaTest(null);
      await abrir(tester, MockClient((_) async => fail('no tenía que llamar a Google')));
      expect(find.textContaining('Configuración › Asistente IA'), findsOneWidget);
      final boton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Leer con IA'));
      expect(boton.onPressed, isNull);
    });
  });

  group('vincular con los productos', () {
    testWidgets('con el proveedor reconocido por su CUIT, propone el producto parecido (amarillo) y lo muestra', (tester) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      await producto('Crema simple 200 gr', proveedorId: elpar);
      await abrir(tester, ia());
      await leer(tester);
      expect(find.text('Proveedor: Distribuidora Elpar'), findsOneWidget);
      expect(find.byTooltip('Parecido de nombre: confirmalo'), findsOneWidget);
      expect(find.text('Crema simple 200 gr'), findsWidgets);
      expect(find.text('Aprender estos vínculos (1)'), findsOneWidget);
      expect(find.text('Reconocí 1 de 1 productos:'), findsOneWidget);
      expect(find.text('1 para confirmar'), findsOneWidget);
    });

    testWidgets('"Aprender" guarda el vínculo y la línea pasa a verde', (tester) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      final crema = await producto('Crema simple 200 gr', proveedorId: elpar);
      await abrir(tester, ia());
      await leer(tester);
      await tester.tap(find.text('Aprender estos vínculos (1)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aprendí 1 vínculo'), findsOneWidget);
      expect(find.byTooltip('Aprendido de facturas anteriores'), findsOneWidget);
      expect(find.text('1 seguros'), findsOneWidget);
      expect(find.text('1 para confirmar'), findsNothing);
      final vinculos = await vinculosDe(db, elpar);
      expect(vinculos.every((v) => v.productoId == crema), isTrue);
      expect(vinculos, isNotEmpty);
    });

    testWidgets('si no conoce al proveedor lo pregunta, y al elegirlo aprende su CUIT', (tester) async {
      await producto('Crema simple 200 gr', proveedorId: elpar);
      await abrir(tester, ia());
      await leer(tester);
      expect(find.textContaining('No conozco a este proveedor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('elegir_proveedor_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Distribuidora Elpar').last);
      await tester.pumpAndSettle();
      expect(find.text('Proveedor: Distribuidora Elpar'), findsOneWidget);
      expect((await proveedorPorCuit(db, '30708174757'))!.id, elpar);
    });

    testWidgets('lo que el parecido no resuelve se lo pide a la IA, y queda en amarillo para confirmar', (tester) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      final postre = await producto('Lácteo cremoso de mesa', proveedorId: elpar);
      await abrir(tester, ia(vinculaAlProducto: postre));
      await leer(tester);
      expect(find.byTooltip('Lo sugirió la IA: confirmalo'), findsOneWidget);
      expect(find.text('Lácteo cremoso de mesa'), findsWidgets);
    });

    testWidgets('si la IA falla para vincular, avisa y deja la línea sin vincular', (tester) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      await producto('Lácteo cremoso de mesa', proveedorId: elpar);
      await abrir(tester, ia(estadoVinculos: 429));
      await leer(tester);
      expect(find.textContaining('La IA no pudo ayudar con los vínculos'), findsOneWidget);
      expect(find.byTooltip('Sin vincular: elegí un producto'), findsOneWidget);
      expect(find.text('Cierra con el total impreso'), findsOneWidget); // la lectura sigue andando
    });

    testWidgets('las unidades por cantidad cambian el costo por unidad', (tester) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      await producto('Crema simple 200 gr', proveedorId: elpar);
      await abrir(tester, ia());
      await leer(tester);
      expect(find.textContaining('2.194'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '6');
      await tester.pumpAndSettle();
      // 4 × 6 = 24 unidades: 8.774,21 / 24 = 365,59 → $366 c/u.
      expect(find.textContaining('366'), findsWidgets);
      expect(find.textContaining('2.194'), findsNothing);
    });
  });

  group('bultos y unidades', () {
    Future<int> conCosto(int centavos) async {
      await asociarCuit(db, proveedorId: elpar, cuit: '30708174757');
      return db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Crema simple 200 gr', proveedorId: Value(elpar), costoCentavos: Value(centavos)));
    }

    String valorDeUnidades(WidgetTester tester) {
      final campo = tester.widget<TextFormField>(find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('unidades_') == true));
      return campo.initialValue!;
    }

    testWidgets('si la factura cobra unas 24 veces tu costo, propone un bulto de 24 y lo avisa', (tester) async {
      // La factura da $2.194 por cantidad y la descripción trae "(24)": tu unidad cuesta $91.
      await conCosto(9100);
      await abrir(tester, ia());
      await leer(tester);
      expect(valorDeUnidades(tester), '24');
      expect(find.text('4 bultos × 24'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Bulto de 24:')), findsOneWidget); // explica por qué
    });

    testWidgets('si el costo se parece al tuyo, la factura cuenta unidades sueltas y queda en 1', (tester) async {
      await conCosto(210000);
      await abrir(tester, ia());
      await leer(tester);
      expect(valorDeUnidades(tester), '1');
      expect(find.textContaining('bultos ×'), findsNothing);
    });

    testWidgets('sin costo cargado no se adivina el bulto: queda en 1 con el aviso de lo que dice la descripción', (tester) async {
      await conCosto(0);
      await abrir(tester, ia());
      await leer(tester);
      expect(valorDeUnidades(tester), '1');
      expect(find.byTooltip('La descripción menciona un pack de 24. Si la factura cuenta bultos, poné 24 en "× unid.".'), findsOneWidget);
    });

    testWidgets('lo aprendido manda: no se pisa con la propuesta', (tester) async {
      final crema = await conCosto(9100);
      await aprenderVinculo(db, proveedorId: elpar, productoId: crema, codigo: null, descripcion: '1042 - CREMA SIMPLE X 200 GR (24)', unidadesPorCantidad: 1);
      await abrir(tester, ia());
      await leer(tester);
      expect(valorDeUnidades(tester), '1');
    });
  });
}
