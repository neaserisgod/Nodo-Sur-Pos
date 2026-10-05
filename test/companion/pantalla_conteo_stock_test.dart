// Conteo de stock del celular (mock del 2026-10-04): lo que no se puede romper es
// que un campo vacío NO toca el stock, que lo cargado se guarda como valor contado
// con su rastro ("Conteo físico"), que el tilde copia lo guardado y que un
// pesable se cuenta en gramos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_conteo_stock.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Las cargas hablan con una base real (drift): hace falta dejar correr el
/// reloj de verdad entre cuadros, no solo bombear los de test.
Future<void> _asentar(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  }
  await t.pump();
}

class _Escenario {
  _Escenario(this.db, this.puerto, this.proveedores);
  final AppDatabase db;
  final PuertoLocal puerto;
  final List<int> proveedores;
}

Future<_Escenario> _preparar(WidgetTester t) async {
  tester(t);
  SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Dueño'});
  final db = (await t.runAsync(() async => baseDeTest()))!;
  usarBaseLocalDeTest(db);
  final puerto = PuertoLocal(baseLocalCompanion());
  final provs = (await t.runAsync(() => puerto.proveedores()))!;
  return _Escenario(db, puerto, [provs[0].id, provs[1].id]);
}

// Un celular parado: el viewport por defecto (800×600) no representa la pantalla real (TRAMPAS.md).
void tester(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> _abrir(WidgetTester t, {int? proveedorId, bool soloSinStock = false}) async {
  await t.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaConteoStock(proveedorId: proveedorId, soloSinStock: soloSinStock)));
  await _asentar(t);
}

/// El campo de conteo de la fila de [nombre].
Finder _campo(String nombre) => find.descendant(of: _fila(nombre), matching: find.byType(TextField));

Finder _fila(String nombre) => find.byKey(ValueKey('conteo:$nombre'));

/// El tilde "Está igual que lo guardado": el último botón de la fila.
Finder _igualDe(String nombre) => find.descendant(of: _fila(nombre), matching: find.byType(PresionNs)).last;

Future<int> _stockDe(WidgetTester t, AppDatabase db, int id) async =>
    (await t.runAsync(() => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()))!.stock;

void main() {
  testWidgets('lo que no se toca no cambia; lo tocado guarda el valor contado con su rastro', (t) async {
    final e = await _preparar(t);
    final cerveza = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    final agua = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Agua', esPesable: false, stock: 30, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t, proveedorId: e.proveedores[0]);

    await t.enterText(_campo('Cerveza'), '13');
    await t.pump();
    expect(find.textContaining('Guardar conteo (1 de 2)'), findsOneWidget);
    expect(find.text('+1 u. de diferencia'), findsOneWidget);

    await t.tap(find.textContaining('Guardar conteo (1 de 2)'));
    await _asentar(t);
    await t.pump(const Duration(seconds: 4)); // el aviso flotante se va solo

    expect(await _stockDe(t, e.db, cerveza), 13);
    expect(await _stockDe(t, e.db, agua), 30, reason: 'el agua no se tocó: su stock queda como estaba');
    final movimientos = (await t.runAsync(() => (e.db.select(e.db.movimientosDeStock)..where((m) => m.productoId.equals(cerveza))).get()))!;
    expect(movimientos.last.motivo, 'Conteo físico');
    final delAgua = (await t.runAsync(() => (e.db.select(e.db.movimientosDeStock)..where((m) => m.productoId.equals(agua))).get()))!;
    expect(delAgua.where((m) => m.motivo == 'Conteo físico'), isEmpty, reason: 'sin tocar, no deja ningún movimiento de conteo');
    expect(find.textContaining('Guardar conteo ('), findsNothing, reason: 'tras guardar se limpia lo cargado');
  });

  testWidgets('el tilde copia lo guardado: cuenta como contado y no mueve el stock', (t) async {
    final e = await _preparar(t);
    final cerveza = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t, proveedorId: e.proveedores[0]);

    await t.tap(_igualDe('Cerveza'));
    await t.pump();
    expect(find.text('Coincide con lo guardado'), findsOneWidget);
    await t.tap(find.textContaining('Guardar conteo (1 de 1)'));
    await _asentar(t);
    await t.pump(const Duration(seconds: 4)); // el aviso flotante se va solo

    expect(await _stockDe(t, e.db, cerveza), 12);
    final movimientos = (await t.runAsync(() => (e.db.select(e.db.movimientosDeStock)..where((m) => m.productoId.equals(cerveza))).get()))!;
    expect(movimientos.where((m) => m.motivo == 'Conteo físico'), isEmpty, reason: 'sin diferencia no hay movimiento de stock que registrar');
  });

  testWidgets('sin nada cargado el botón de guardar está apagado', (t) async {
    final e = await _preparar(t);
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1));
    await _abrir(t, proveedorId: e.proveedores[0]);

    expect(find.text('Guardar conteo'), findsOneWidget);
    await t.tap(find.text('Guardar conteo'));
    await _asentar(t);
    await t.pump(const Duration(seconds: 4)); // el aviso flotante se va solo
    expect(find.textContaining('Guardado:'), findsWidgets, reason: 'tocarlo apagado no guarda nada: solo quedan los "Guardado: 12 u." de las filas');
  });

  testWidgets('un valor inválido avisa y no se guarda', (t) async {
    final e = await _preparar(t);
    final id = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 1, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t, proveedorId: e.proveedores[0]);

    await t.enterText(_campo('Cerveza'), 'abc');
    await t.pump();
    expect(find.text('Número inválido'), findsOneWidget);
    await t.tap(find.textContaining('Guardar conteo'));
    await _asentar(t);
    await t.pump(const Duration(seconds: 4)); // el aviso flotante se va solo

    expect(await _stockDe(t, e.db, id), 1);
  });

  testWidgets('"Productos sin stock" muestra solo lo agotado, de todos los proveedores', (t) async {
    final e = await _preparar(t);
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 12, proveedorId: e.proveedores[0], usuarioId: 1));
    await t.runAsync(() => e.puerto.crearProducto(nombre: 'Yerba', esPesable: false, stock: 0, proveedorId: e.proveedores[1], usuarioId: 1));
    await _abrir(t, soloSinStock: true);

    expect(find.text('Cerveza'), findsNothing);
    expect(find.text('Yerba'), findsOneWidget);
    expect(find.text('Productos sin stock'), findsOneWidget);
  });

  testWidgets('un pesable se cuenta en gramos y guarda gramos', (t) async {
    final e = await _preparar(t);
    final id = (await t.runAsync(() => e.puerto.crearProducto(nombre: 'Jamón', esPesable: true, precioPorKiloCentavos: 1000000, stockGramos: 3200, proveedorId: e.proveedores[0], usuarioId: 1)))!;
    await _abrir(t, proveedorId: e.proveedores[0]);

    expect(find.text('Guardado: 3200 g'), findsOneWidget);
    await t.enterText(_campo('Jamón'), '2750');
    await t.pump();
    expect(find.text('−450 g de diferencia'), findsOneWidget);
    await t.tap(find.textContaining('Guardar conteo (1 de 1)'));
    await _asentar(t);
    await t.pump(const Duration(seconds: 4)); // el aviso flotante se va solo

    final guardado = (await t.runAsync(() => (e.db.select(e.db.productos)..where((p) => p.id.equals(id))).getSingle()))!;
    expect(guardado.stockGramos, 2750);
  });
}
