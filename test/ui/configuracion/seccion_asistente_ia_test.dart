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

/// La cuenta del negocio simulada (El dueño, 2026-10-07: "la clave es por cuenta").
class _Cuenta implements AccesoIaCuenta {
  _Cuenta({required this.puedeCambiar, this.configurada = false});
  final bool puedeCambiar;
  bool configurada;
  String? clave;

  @override
  Future<({bool configurada, String? modelo, bool puedeCambiar})?> estado() async =>
      (configurada: configurada, modelo: 'gemini-3.5-flash-lite', puedeCambiar: puedeCambiar);
  @override
  Future<void> guardarClave(String? clave, {String? modelo}) async {
    this.clave = clave;
    configurada = clave != null;
  }

  @override
  Future<({int estado, String cuerpo})> generar({required String modelo, required String cuerpo, required Duration limite}) async =>
      (estado: 200, cuerpo: _ok);
}

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

  group('clave del negocio, en la cuenta', () {
    testWidgets('el dueño la guarda en la cuenta y lo dice', (tester) async {
      final cuenta = _Cuenta(puedeCambiar: true);
      await ClaveGemini.conectarCuenta(cuenta);
      await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
      await tester.pumpAndSettle();
      expect(find.textContaining('la usan todos tus equipos'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'AIza-del-negocio');
      await tester.tap(find.text('Guardar y probar'));
      await tester.pumpAndSettle();
      expect(cuenta.clave, 'AIza-del-negocio');
      expect(ClaveGemini.valor, isNull);
      expect(find.textContaining('en la cuenta del negocio'), findsOneWidget);
    });

    testWidgets('un empleado con la clave del negocio no tiene nada que cargar', (tester) async {
      await ClaveGemini.conectarCuenta(_Cuenta(puedeCambiar: false, configurada: true));
      await _montar(tester, MockClient((_) async => http.Response(_ok, 200)));
      await tester.pumpAndSettle();
      expect(find.textContaining('La carga o la cambia el dueño'), findsOneWidget);
      expect(find.textContaining('Clave de la API'), findsNothing);
      expect(find.text('Guardar y probar'), findsNothing);
    });
  });
}
