import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/bienvenida/bienvenida_gastro.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/edicion.dart';

/// La bienvenida de Nodo Gastro (mock v5): tres pantallas que se pasan con "Siguiente", y "Ya tengo cuenta" la saltea.
void main() {
  setUp(() => edicionActual = Edicion.gastronomia);
  tearDown(() => edicionActual = Edicion.almacen);

  Future<List<String>> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final terminado = <String>[];
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: BienvenidaGastro(alTerminar: (_) => terminado.add('listo'))));
    await tester.pumpAndSettle();
    return terminado;
  }

  testWidgets('se pasa de a una y "Empezar" la termina', (tester) async {
    final terminado = await abrir(tester);
    expect(find.textContaining('atiende solo.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bienvenida-siguiente')));
    await tester.pumpAndSettle();
    expect(find.textContaining('manda.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bienvenida-siguiente')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cierra sola.'), findsOneWidget);
    expect(find.text('Empezar'), findsOneWidget);
    expect(terminado, isEmpty);

    await tester.tap(find.byKey(const Key('bienvenida-siguiente')));
    expect(terminado, ['listo']);
  });

  testWidgets('"Ya tengo cuenta" la saltea desde cualquier pantalla', (tester) async {
    final terminado = await abrir(tester);
    await tester.tap(find.byKey(const Key('bienvenida-saltar')));
    expect(terminado, ['listo']);
  });
}
