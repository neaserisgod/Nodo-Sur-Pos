// La pantalla del asistente con IA (Nodo Sur Servicios): sin clave lo dice; con clave pregunta, muestra la respuesta y las
// acciones propuestas, validadas (lo que la IA inventa no aparece). La IA es falsa: contesta lo que el test le pone.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_asistente_ia_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

class _IaFalsa implements AccesoIaCuenta {
  _IaFalsa(this.respuesta);
  final Map<String, Object?> respuesta;
  String? pedido;

  @override
  Future<({bool configurada, String? modelo, bool puedeCambiar})?> estado() async => (configurada: true, modelo: null, puedeCambiar: false);

  @override
  Future<void> guardarClave(String? clave, {String? modelo}) async {}

  @override
  Future<({int estado, String cuerpo})> generar({required String modelo, required String cuerpo, required Duration limite}) async {
    pedido = cuerpo;
    return (
      estado: 200,
      cuerpo: jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': jsonEncode(respuesta)},
              ],
            },
          },
        ],
      }),
    );
  }
}

void main() {
  late AppDatabase db;
  late int corte;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
    usarBaseLocalDeTest(db);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    corte = await crearServicio(db, nombre: 'Corte', precioCentavos: 800000, duracionMinutos: 30, usuarioId: usuario);
  });
  tearDown(() async {
    ClaveGemini.fijarParaTest(null);
    await db.close();
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: const PantallaAsistenteIaNs()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin clave de IA lo dice y no muestra el campo', (tester) async {
    ClaveGemini.fijarParaTest(null);
    await abrir(tester);
    expect(find.textContaining('cargá la clave de la IA'), findsOneWidget);
    expect(find.byKey(const Key('asistente_ia_campo')), findsNothing);
  });

  testWidgets('pregunta y muestra la respuesta con la acción válida; la inventada no', (tester) async {
    final manana = DateTime.now().add(const Duration(days: 1));
    String dos(int n) => n.toString().padLeft(2, '0');
    final ia = _IaFalsa({
      'respuesta': 'Mañana a las 10 está libre.',
      'acciones': [
        {'tipo': 'dar_turno', 'servicio_id': corte, 'inicio': '${manana.year}-${dos(manana.month)}-${dos(manana.day)}T10:00', 'cliente': 'Juana'},
        {'tipo': 'dar_turno', 'servicio_id': 999, 'inicio': '${manana.year}-${dos(manana.month)}-${dos(manana.day)}T10:00', 'cliente': 'Eva'},
      ],
    });
    ClaveGemini.fijarParaTest(null, cuenta: ia, enCuenta: true);
    await abrir(tester);

    await tester.enterText(find.descendant(of: find.byKey(const Key('asistente_ia_campo')), matching: find.byType(TextField)), 'Dale un turno a Juana mañana a las 10');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('asistente_ia_enviar')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.text('Mañana a las 10 está libre.'), findsOneWidget);
    expect(find.textContaining('Turno para Juana: Corte'), findsOneWidget);
    expect(find.textContaining('Eva'), findsNothing);
    expect(find.textContaining('no se puede hacer'), findsOneWidget);
    // Los datos del negocio viajan con la pregunta.
    expect(ia.pedido, contains('Corte'));
    expect(ia.pedido, contains('Dale un turno a Juana'));
  });
}
