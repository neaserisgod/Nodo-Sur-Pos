// Bienvenida del primer arranque (`bienvenida/`): recorrer las escenas, saltarla, y el "Listo" después de entrar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/bienvenida/pantalla_bienvenida.dart';
import 'package:la_plazoleta/companion/bienvenida/pantalla_listo.dart';
import 'package:la_plazoleta/companion/flujo_modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_elegir_modo.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Con las animaciones apagadas, igual que "reducir animaciones" en el celular: cada "Siguiente" salta directo a la
/// parada de la escena y `pumpAndSettle` vuelve (las partículas no animan).
Widget _app(Widget home) => MaterialApp(
  theme: TemaCompanion.claro,
  builder: (context, child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
  home: home,
);

/// flutter_test no carga las fuentes del pubspec: sin Figtree los textos se dibujan con Ahem (cajas anchas) y
/// desbordan por culpa del test, no de la app (mismo arreglo que `capturas_companion_test.dart`).
Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

void main() {
  setUpAll(_cargarFigtree);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> tamanioCelular(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('recorre las seis escenas con Siguiente y termina con Empezar', (tester) async {
    await tamanioCelular(tester);
    var terminada = 0;
    await tester.pumpWidget(_app(PantallaBienvenida(alTerminar: (_) => terminada++)));
    await tester.pumpAndSettle();

    final siguiente = find.byKey(const Key('bienvenida-siguiente'));
    // Cada escena, con algo que solo ella muestra.
    final esperado = <String>[
      'Tu almacén,',
      r'$987.500', // cuánto separar para los proveedores
      'Primero se cuenta. Después, la diferencia.',
      'Todo se pone al día cuando vuelve.',
      'Había 12 en el sistema',
      'Configuremos este celular: son dos pasos.',
    ];
    for (var i = 0; i < esperado.length; i++) {
      expect(find.text(esperado[i]), findsOneWidget, reason: 'escena $i');
      expect(find.text(i == esperado.length - 1 ? 'Empezar' : 'Siguiente'), findsOneWidget);
      if (i < esperado.length - 1) {
        await tester.tap(siguiente);
        await tester.pumpAndSettle();
      }
    }
    expect(terminada, 0);
    expect(find.byKey(const Key('bienvenida-saltar')), findsNothing, reason: 'en la última no hay nada que saltar');
    await tester.tap(siguiente);
    expect(terminada, 1);
  });

  testWidgets('"Tu almacén, en orden." pasa a "Tu plata, en orden." en la segunda escena', (tester) async {
    await tamanioCelular(tester);
    await tester.pumpWidget(_app(PantallaBienvenida(alTerminar: (_) {}, pasoInicial: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Tu plata,'), findsOneWidget);
    expect(find.text('en orden.'), findsOneWidget);
    expect(find.text('Te queda a vos'), findsOneWidget);
  });

  testWidgets('Saltar termina la bienvenida desde cualquier escena', (tester) async {
    await tamanioCelular(tester);
    var terminada = 0;
    await tester.pumpWidget(_app(PantallaBienvenida(alTerminar: (_) => terminada++, pasoInicial: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bienvenida-saltar')));
    expect(terminada, 1);
  });

  testWidgets('en una instalación nueva, terminar la bienvenida lleva a elegir el modo', (tester) async {
    await tamanioCelular(tester);
    await tester.pumpWidget(_app(pantallaDeBienvenidaInicial()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bienvenida-saltar')));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaElegirModo), findsOneWidget);
    expect(find.byType(PantallaBienvenida), findsNothing, reason: 'no se vuelve atrás a la bienvenida');
  });

  testWidgets('cada escena se dibuja a mitad de su transición sin desbordes', (tester) async {
    await tamanioCelular(tester);
    for (final s in [0.4, 1.9, 2.7, 4.3, 4.7, 5.8, 6.3, 7.0, 7.5, 8.2, 9.1, 9.9, 10.5, 11.2, 11.8, 12.4]) {
      await tester.pumpWidget(_app(PantallaBienvenida(key: ValueKey(s), alTerminar: (_) {}, segundoFijo: s)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'segundo $s');
    }
  });

  testWidgets('Listo saluda con el nombre del perfil y sigue al inicio', (tester) async {
    await tamanioCelular(tester);
    var siguio = 0;
    await tester.pumpWidget(_app(PantallaListo(nombre: 'Bruno', alSeguir: (_) => siguio++)));
    await tester.pumpAndSettle();
    expect(find.text('Listo, Bruno.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('listo-seguir')));
    expect(siguio, 1);
  });

  testWidgets('Listo sin nombre guardado no queda con una coma colgando', (tester) async {
    await tamanioCelular(tester);
    await tester.pumpWidget(_app(PantallaListo(alSeguir: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Listo.'), findsOneWidget);
  });
}
