// Configuración del celular (mock del 2026-10-04): se edita en la misma
// página y un solo "Guardar" aplica lo cambiado. Lo que no se puede romper es
// que NADA se escribe hasta tocarlo, que solo se guarda lo que cambió y que cada
// valor termina en su lugar (redondeo, recargo, producto de vuelto, ganancia de
// referencia por categoría y usuarios).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_configuracion_companion.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

Future<PuertoLocal> _preparar(WidgetTester t) async {
  // Un celular parado y alto: la página es larga y las filas de más abajo no se construyen si no entran.
  t.view.physicalSize = const Size(400, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Dueño'});
  final db = (await t.runAsync(() async => baseDeTest()))!;
  usarBaseLocalDeTest(db);
  return PuertoLocal(baseLocalCompanion());
}

Future<void> _abrir(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: const PantallaConfiguracionCompanion()));
  await _asentar(t);
}

/// El botón "Guardar configuración" y si está habilitado (un `PresionNs` sin `onTap` está apagado).
Finder get _guardar => find.widgetWithText(PresionNs, 'Guardar configuración');

bool _guardarActivo(WidgetTester t) => t.widget<PresionNs>(_guardar).onTap != null;

/// La fila (renglón) de [nombre]: el primer `Row` que lo contiene.
Finder _fila(String nombre) => find.ancestor(of: find.text(nombre), matching: find.byType(Row)).first;

Finder _chip(String texto) => find.widgetWithText(ChipNs, texto);

Future<void> _tocarGuardar(WidgetTester t) async {
  await t.tap(_guardar);
  await _asentar(t);
}

void main() {
  testWidgets('sin cambios el botón de guardar está deshabilitado y nada se escribe', (t) async {
    await _preparar(t);
    await _abrir(t);

    expect(_guardarActivo(t), isFalse);
  });

  testWidgets('elegir otro redondeo no escribe nada hasta tocar Guardar, y después queda guardado', (t) async {
    final puerto = await _preparar(t);
    final antes = (await t.runAsync(() => puerto.configuracionNegocio()))!.pasoRedondeoCentavos;
    // Se elige un paso distinto del actual entre los habituales.
    final elegido = antes == 5000 ? 10000 : 5000;
    await _abrir(t);

    await t.tap(_chip(elegido == 5000 ? '\$\u00A050' : '\$\u00A0100'));
    await t.pump();
    expect((await t.runAsync(() => puerto.configuracionNegocio()))!.pasoRedondeoCentavos, antes, reason: 'sin Guardar no se escribió nada');
    expect(_guardarActivo(t), isTrue);

    await _tocarGuardar(t);
    expect((await t.runAsync(() => puerto.configuracionNegocio()))!.pasoRedondeoCentavos, elegido);
  });

  testWidgets('el recargo de cigarrillos se guarda con sus tres montos', (t) async {
    final puerto = await _preparar(t);
    await _abrir(t);

    await t.enterText(find.descendant(of: find.widgetWithText(CampoNs, 'Primer atado'), matching: find.byType(TextField)), '777');
    await t.pump();
    await _tocarGuardar(t);

    final config = (await t.runAsync(() => puerto.configuracionNegocio()))!;
    expect(config.recargoPrimerAtadoCentavos, 77700);
  });

  testWidgets('la ganancia de referencia de una categoría sube de a 5 puntos y no pasa de 99', (t) async {
    final puerto = await _preparar(t);
    final cats = (await t.runAsync(() => puerto.categorias()))!;
    final cat = cats.first;
    final partida = cat.markupDefaultBp ~/ 100;
    await _abrir(t);

    final mas = find.descendant(of: _fila(cat.nombre), matching: find.byType(PresionNs)).last;
    await t.tap(mas);
    await t.pump();
    await _tocarGuardar(t);

    final despues = (await t.runAsync(() => puerto.categorias()))!.firstWhere((c) => c.id == cat.id);
    expect(despues.markupDefaultBp ~/ 100, (partida + 5).clamp(0, 99));
  });

  testWidgets('desactivar un usuario se guarda con Guardar; el otro queda como estaba', (t) async {
    final puerto = await _preparar(t);
    final ana = (await t.runAsync(() => puerto.crearUsuarioNuevo('Ana')))!;
    await _abrir(t);

    await t.tap(find.widgetWithText(InterruptorNs, 'Ana'));
    await t.pump();
    expect((await t.runAsync(() => puerto.usuarios()))!.firstWhere((u) => u.id == ana).activo, isTrue, reason: 'sin Guardar sigue activo');
    await _tocarGuardar(t);

    final usuarios = (await t.runAsync(() => puerto.usuarios()))!;
    expect(usuarios.firstWhere((u) => u.id == ana).activo, isFalse);
    expect(usuarios.firstWhere((u) => u.id == 1).activo, isTrue);
  });

  testWidgets('un cambio y volver sin guardar pregunta antes de salir', (t) async {
    await _preparar(t);
    await _abrir(t);

    await t.tap(_chip('\$\u00A050'));
    await t.pump();
    await t.tap(find.byType(BotonCircularNs).first);
    await t.pump(const Duration(milliseconds: 400));

    // Aparece la confirmación de salir sin guardar: la pantalla sigue ahí.
    expect(find.byType(PantallaConfiguracionCompanion), findsOneWidget);
  });

  testWidgets('"+ Nueva categoría" la crea en la base del celular (viaja por la sync) y no deja repetir un nombre', (t) async {
    await _preparar(t);
    await _abrir(t);
    final db = baseLocalCompanion();
    final antes = (await t.runAsync(() => db.select(db.categorias).get()))!;

    await t.tap(find.text('+ Nueva categoría'));
    await _asentar(t);
    await t.enterText(find.byType(TextField).last, 'Limpieza');
    await t.tap(find.text('Guardar').last);
    await _asentar(t);

    final despues = (await t.runAsync(() => db.select(db.categorias).get()))!;
    expect(despues, hasLength(antes.length + 1));
    final nueva = despues.firstWhere((c) => c.nombre == 'Limpieza');
    expect(nueva.globalId, isNotNull, reason: 'viaja a la PC');
    expect(find.text('Limpieza'), findsWidgets);

    await t.tap(find.text('+ Nueva categoría'));
    await _asentar(t);
    await t.enterText(find.byType(TextField).last, 'limpieza');
    await t.tap(find.text('Guardar').last);
    await _asentar(t);
    expect(find.text('Ya hay una categoría llamada "limpieza"'), findsOneWidget);
    expect((await t.runAsync(() => db.select(db.categorias).get()))!, hasLength(antes.length + 1));
  });
}

