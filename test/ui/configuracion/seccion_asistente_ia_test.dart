import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/ui/configuracion/seccion_asistente_ia.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ok = '{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}';

Future<void> _montar(WidgetTester tester, http.Client client) => tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: Scaffold(body: SingleChildScrollView(child: SeccionAsistenteIa(client: client))),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaveGemini.fijarParaTest(null);
  });

  testWidgets('una clave que anda se guarda y lo dice', (tester) async {
    await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
    await tester.enterText(find.byType(TextField), 'AIza-buena');
    await tester.tap(find.text('Guardar y probar'));
    await tester.pumpAndSettle();
    expect(ClaveGemini.valor, 'AIza-buena');
    expect(find.textContaining('quedó guardada'), findsOneWidget);
  });

  testWidgets('una clave rota muestra el motivo y no se guarda', (tester) async {
    await _montar(tester, MockClient((_) async => http.Response('{"error":{"message":"API key not valid"}}', 400)));
    await tester.enterText(find.byType(TextField), 'AIza-rota');
    await tester.tap(find.text('Guardar y probar'));
    await tester.pumpAndSettle();
    expect(ClaveGemini.configurada, isFalse);
    expect(find.textContaining('no se guardó'), findsOneWidget);
  });

  testWidgets('Quitar clave la borra', (tester) async {
    ClaveGemini.fijarParaTest('AIza-vieja');
    await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
    await tester.tap(find.text('Quitar clave'));
    await tester.pumpAndSettle();
    expect(ClaveGemini.configurada, isFalse);
  });

  group('selector de modelo', () {
    testWidgets('sin clave no se ofrece', (tester) async {
      await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
      expect(find.text('Modelo de la IA'), findsNothing);
    });

    testWidgets('con clave arranca en el más barato y elegir otro lo guarda sin tocar la clave', (tester) async {
      ClaveGemini.fijarParaTest('AIza-buena');
      await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
      expect(find.widgetWithText(TextField, etiquetaDeModelo(modeloGeminiPorDefecto)), findsOneWidget);
      await tester.tap(find.byType(DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(etiquetaDeModelo('gemini-3.8-flash')).last);
      await tester.pumpAndSettle();
      expect(ClaveGemini.modelo, 'gemini-3.8-flash');
      expect(ClaveGemini.valor, 'AIza-buena');
    });
  });
}
