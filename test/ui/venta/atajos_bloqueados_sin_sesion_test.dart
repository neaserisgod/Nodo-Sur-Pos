// Bug real, reportado por Bruno: "puedo vender si cierro caja, no vuelve a
// pedir que se abra". `_manejarTeclaGlobal` (pantalla_venta.dart) es un
// handler de teclado global (`HardwareKeyboard.instance.addHandler`) que no
// sabe nada del árbol de widgets — seguía reaccionando a los atajos Alt+algo
// (accesos directos, Varios, mixto, elegir medio) aunque la caja estuviera
// cerrada y la pantalla mostrara "Caja cerrada." en vez del carrito. Eso
// armaba un carrito fantasma que aparecía recién al reabrir caja.
//
// Arreglo: el handler corta temprano si `c.sesion == null`, igual que ya
// cortaba si había una ruta encima (`ModalRoute.of(context)?.isCurrent`).

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      navigatorObservers: [routeObserver],
      home: PantallaVenta(db: db),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _presionarAlt(
  WidgetTester tester,
  LogicalKeyboardKey tecla,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(tecla);
  await tester.sendKeyUpEvent(tecla);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

// El `Provider` se crea recién dentro del build de `PantallaVenta`, así que
// hay que buscar un contexto por DEBAJO en el árbol (el propio `Scaffold`
// que ese build arma), no el de `PantallaVenta` mismo.
VentaControlador _controladorDe(WidgetTester tester) {
  final elemento = tester.element(find.byType(Scaffold));
  return Provider.of<VentaControlador>(elemento, listen: false);
}

void main() {
  testWidgets(
    'sin sesión abierta, un atajo Alt+tecla NO cambia nada a espaldas de la pantalla',
    (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      // Sesión abierta y ya cerrada, tal como en una caja real que ya operó.
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
      final sesionId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId)))
          .write(const SesionesDeCajaCompanion(estado: Value('CERRADA')));

      await _pump(tester, db);
      expect(find.text('Caja cerrada.'), findsOneWidget);

      // No cambia el medio de pago elegido (Alt+E) a espaldas de la
      // pantalla — el handler global sigue activo aunque la venta esté
      // bloqueada.
      await _presionarAlt(tester, LogicalKeyboardKey.keyE);

      final c = _controladorDe(tester);
      expect(c.medioElegido, isNull);
      expect(c.carrito, isEmpty);
    },
  );

  testWidgets(
    'sesión de un día anterior sin cerrar, un atajo Alt+tecla NO cambia nada a espaldas de la pantalla',
    (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
      await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
              fechaApertura: Value(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
            ),
          );

      await _pump(tester, db);
      expect(
        find.text('Queda una sesión de un día anterior sin cerrar.'),
        findsOneWidget,
      );

      await _presionarAlt(tester, LogicalKeyboardKey.keyE);

      final c = _controladorDe(tester);
      expect(c.medioElegido, isNull);
      expect(c.carrito, isEmpty);
    },
  );
}
