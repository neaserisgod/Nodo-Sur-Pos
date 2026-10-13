// Al abrir, un cambio de negocio no se pudo terminar: la app no sigue con media cuenta puesta (2026-10-13, blindaje).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/companion_app.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

void main() {
  Future<void> abrir(WidgetTester t, {required Future<void> Function() reintentar, required void Function() alTerminar}) async {
    await t.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: PantallaCambioTrabado(error: 'disco lleno', reintentar: reintentar, alTerminar: (_) => alTerminar()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('muestra qué pasó, dice que no se perdió nada y no deja seguir sin terminar', (t) async {
    await abrir(t, reintentar: () async {}, alTerminar: () {});
    expect(find.text('No se pudo terminar de cambiar de negocio'), findsOneWidget);
    expect(find.textContaining('Ningún dato se perdió'), findsOneWidget);
    expect(find.textContaining('disco lleno'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('reintentar que sale bien sigue; uno que falla muestra el error nuevo y deja probar otra vez', (t) async {
    var intentos = 0;
    var termino = false;
    await abrir(t, reintentar: () async {
      intentos++;
      if (intentos == 1) throw StateError('sigue trabado');
    }, alTerminar: () => termino = true);
    await t.tap(find.byKey(const Key('reintentar_cambio')));
    await t.pumpAndSettle();
    expect(termino, isFalse);
    expect(find.textContaining('sigue trabado'), findsOneWidget);
    await t.tap(find.byKey(const Key('reintentar_cambio')));
    await t.pumpAndSettle();
    expect(termino, isTrue);
    expect(intentos, 2);
  });
}
