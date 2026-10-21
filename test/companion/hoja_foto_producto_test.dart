// La foto de un plato para el catálogo de WhatsApp (El dueño, 2026-10-21: "sacar una foto y que se ponga ahí"): se saca, sube a
// Nodo Sur (que la pasa al bot) y se puede quitar. La cámara no existe en las pruebas: se reemplaza por una foto fija.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/pantallas/hoja_foto_producto_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import '../helpers/controlador_falso_ns.dart';
import '../helpers/sitio_bot_falso.dart';

// Un PNG de 1×1: Image.memory lo puede dibujar.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const _mila = ProductoCompanion(id: 1, nombre: 'Milanesa con papas', esPesable: false, precioCentavos: 650000, stock: 0, activo: true, globalId: 'g-mila');

Future<void> _abrir(WidgetTester t, SitioBotFalso bot, {required List<ImageSource> pedidas}) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TemaCompanion.claro,
      home: AppNs(
        controlador: ControladorFalsoNs(),
        version: 0,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => mostrarHojaFotoProducto(context, bot: bot, producto: _mila, elegir: (origen) async {
                  pedidas.add(origen);
                  return _png;
                }),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await _esperar(t);
}

Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('sin foto: lo dice; al sacarla sube con el global_id del plato y se ve', (t) async {
    final bot = SitioBotFalso();
    final pedidas = <ImageSource>[];
    await _abrir(t, bot, pedidas: pedidas);
    expect(find.text('Todavía no tiene foto: en WhatsApp va una genérica.'), findsOneWidget);
    expect(find.text('Quitar la foto'), findsNothing);

    await t.tap(find.text('Sacar foto'));
    await _esperar(t);
    expect(pedidas, [ImageSource.camera]);
    expect(bot.fotos['g-mila'], _png);
    expect(find.byKey(const Key('foto_producto')), findsOneWidget);
    expect(find.text('Quitar la foto'), findsOneWidget);
    await t.pump(const Duration(seconds: 3)); // el aviso de arriba se va solo
  });

  testWidgets('con foto: la muestra, se elige otra de la galería y se puede quitar', (t) async {
    final bot = SitioBotFalso()..fotos['g-mila'] = [..._png];
    final pedidas = <ImageSource>[];
    await _abrir(t, bot, pedidas: pedidas);
    expect(find.byKey(const Key('foto_producto')), findsOneWidget);

    await t.tap(find.text('Elegir de la galería'));
    await _esperar(t);
    expect(pedidas, [ImageSource.gallery]);
    expect(bot.fotos['g-mila'], _png);

    await t.tap(find.text('Quitar la foto'));
    await _esperar(t);
    expect(bot.fotos.containsKey('g-mila'), isFalse);
    expect(find.text('Todavía no tiene foto: en WhatsApp va una genérica.'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });
}
