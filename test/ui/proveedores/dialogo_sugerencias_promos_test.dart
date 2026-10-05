import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/ui/proveedores/dialogo_promos.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/base_para_tests.dart';

/// "Sugerir promos" (El dueño, 2026-10-05): los pares que ya se llevan juntos, con nombre de la IA si hay clave.
void main() {
  late AppDatabase db;
  late int usuarioId;

  Future<int> producto(String nombre, int costo, int precio) =>
      db.into(db.productos).insert(ProductosCompanion.insert(nombre: nombre, costoCentavos: Value(costo), precioCentavos: Value(precio), stock: const Value(10)));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest(null);
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final yerba = await producto('Yerba Taragüí', 100000, 140000);
    final galletitas = await producto('Galletitas Terrabusi', 50000, 90000);
    final fideos = await producto('Fideos', 40000, 80000);
    Future<void> venta(List<int> ids) async {
      final v = await db.into(db.ventas).insert(VentasCompanion.insert(sesionCajaId: sesion, usuarioId: usuarioId, subtotalCentavos: 0, totalCentavos: 0));
      for (final id in ids) {
        await db.into(db.lineasDeVenta).insert(LineasDeVentaCompanion.insert(ventaId: v, productoId: Value(id), nombreProductoFoto: 'x', cantidad: const Value(1), precioUnitarioCentavos: 100));
      }
    }

    for (var i = 0; i < 4; i++) {
      await venta([yerba, galletitas]);
    }
    for (var i = 0; i < 8; i++) {
      await venta([fideos]);
    }
  });
  tearDown(() => db.close());

  Future<void> abrirSugerencias(WidgetTester tester, {http.Client? ia}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => mostrarDialogoPromos(context, db: db, usuarioId: usuarioId, clienteIa: ia), child: const Text('abrir')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sugerir promos'));
    await tester.pumpAndSettle();
  }

  testWidgets('sin clave: muestra el par con su nombre simple y avisa cómo activar la IA', (tester) async {
    await abrirSugerencias(tester);
    expect(find.text('Yerba Taragüí + Galletitas Terrabusi'), findsOneWidget);
    expect(find.textContaining('Se llevaron juntos en 4 ventas'), findsOneWidget);
    expect(find.textContaining('Configuración › Asistente IA'), findsOneWidget);
  });

  testWidgets('con clave: la IA le pone nombre y motivo', (tester) async {
    ClaveGemini.fijarParaTest('AIza-buena');
    const respuesta =
        '{"candidates":[{"content":{"parts":[{"text":"{\\"promos\\":[{\\"i\\":0,\\"nombre\\":\\"Merienda Dulce\\",\\"motivo\\":\\"Van juntos seguido.\\"}]}"}]}}]}';
    await abrirSugerencias(tester, ia: MockClient((_) async => http.Response(respuesta, 200)));
    expect(find.text('Merienda Dulce'), findsOneWidget);
    expect(find.text('Van juntos seguido.'), findsOneWidget);
  });

  testWidgets('si la IA falla, las sugerencias se ven igual', (tester) async {
    ClaveGemini.fijarParaTest('AIza-buena');
    await abrirSugerencias(tester, ia: MockClient((_) async => http.Response('{}', 429)));
    expect(find.text('Yerba Taragüí + Galletitas Terrabusi'), findsOneWidget);
    expect(find.textContaining('cupo gratis'), findsOneWidget);
  });

  testWidgets('"Crear" abre el creador con el nombre, los artículos y el precio ya puestos', (tester) async {
    await abrirSugerencias(tester);
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva promo'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Yerba Taragüí + Galletitas Terrabusi'), findsOneWidget);
    // 15 %: costo 1.500 / 0,85 → 1.800 (sueltos 2.300).
    expect(find.textContaining('1.800'), findsWidgets);
  });
}
