// `_manejarTeclaGlobal` (pantalla_venta.dart) se registra con
// `HardwareKeyboard.instance.addHandler` en el `initState` de `PantallaVenta`
// y se saca recién en su `dispose`. Abrir un diálogo con `showDialog`, o
// navegar a otra pantalla con `Navigator.push`, NO desmonta `PantallaVenta`
// — es una ruta más arriba en el `Navigator`, la de abajo sigue viva.
// `HardwareKeyboard` es un registro global de callbacks, no algo scoped al
// árbol de widgets: no tenía forma de saber que había algo encima.
//
// Bug real, encontrado antes de construir Alt+Q/Alt+D para la fase 12 (cobro
// por Point) y arreglado acá mismo, aparte de esa fase — ya afectaba a la
// app de hoy. Arreglo: `ModalRoute.of(context)?.isCurrent == false` al
// principio del handler. Detalle completo en TRAMPAS.md.
//
// Los primeros dos tests originalmente afirmaban el bug (antes del arreglo);
// quedaron invertidos para afirmar que está resuelto. El tercero cubre el
// caso que solo se había confirmado por lectura de código: una pantalla
// pusheada (no un diálogo) encima de la venta.
//
// El primer test usaba Alt+Q como la tecla de prueba. Desde la fase 12,
// Alt+Q tiene un significado LOCAL dentro del diálogo de mixto
// (`CallbackShortcuts` en `dialogo_mixto.dart`: confirma con el resto por
// QR) — presionarla ahí hace algo a propósito, así que ya no sirve para
// probar que el handler GLOBAL no se filtra. Se cambió a Alt+E, que no
// tiene ningún binding local en ese diálogo, para seguir probando
// exactamente lo mismo de siempre: la guarda de `ModalRoute.isCurrent`.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/navbar_superior.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';
import '../../helpers/base_para_tests.dart';

Future<AppDatabase> _crearBaseConSesion() async {
  final db = baseDeTest();
  final usuarioId = await db
      .into(db.usuarios)
      .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: 'Coca-Cola 500ml',
          precioCentavos: const Value(112000),
          stock: const Value(20),
        ),
      );
  return db;
}

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

/// Desde el rediseño 2026-09-25 (segunda pasada) un nombre de producto
/// puede aparecer también como tile permanente de la grilla navegable
/// (`RejillaProductos`) — acota la búsqueda al dropdown de resultados de la
/// barra de búsqueda para que no choque con ese tile.
Finder _enDropdown(String texto) => find.descendant(
  of: find.byKey(const Key('dropdown_resultados_busqueda')),
  matching: find.text(texto),
);

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

/// Simula AltGr en Windows: la tecla física se reporta como `altRight`,
/// pero Windows sintetiza un `controlLeft` junto con ella — así es como
/// `isAltPressed` termina en `true` para un carácter compuesto (`@`, etc.)
/// de un teclado latinoamericano/español, no solo para el atajo real.
Future<void> _presionarAltGr(
  WidgetTester tester,
  LogicalKeyboardKey tecla,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
  await tester.sendKeyDownEvent(tecla);
  await tester.sendKeyUpEvent(tecla);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// La navbar es una fila de pastillas (rediseño "antigravity"): se toca
/// directo la del destino, dentro de la barra.
Future<void> _navegarA(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.descendant(of: find.byType(NavbarSuperior), matching: find.text(etiqueta)).last);
  await tester.pumpAndSettle();
}

/// `Provider.of` desde un contexto por DEBAJO de
/// `ChangeNotifierProvider<VentaControlador>` en el árbol (el `Provider` se
/// crea recién dentro del build de `PantallaVenta`, así que el contexto de
/// `PantallaVenta` mismo queda por ENCIMA y no sirve). `find.descendant`,
/// no `find.byType(Scaffold).first`: con una pantalla pusheada encima hay
/// dos `Scaffold` en el árbol y el orden entre ellos no es de fiar — este
/// busca puntualmente el que está DENTRO de `PantallaVenta`, que sigue
/// montado esté lo que esté encima, un diálogo o una pantalla pusheada.
VentaControlador _controladorDe(WidgetTester tester) {
  final elemento = tester.element(
    find.descendant(
      of: find.byType(PantallaVenta),
      matching: find.byType(Scaffold),
    ),
  );
  return Provider.of<VentaControlador>(elemento, listen: false);
}

void main() {
  group('handler global de teclado vs. algo encima de la venta (bug ya arreglado)', () {
    testWidgets('Alt+E detrás del diálogo de mixto NO cambia medioElegido', (
      tester,
    ) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      await _pump(tester, db);

      await tester.enterText(find.byType(TextField).first, 'coca');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await _presionarAlt(tester, LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(
        find.text('Pago mixto'),
        findsOneWidget,
      ); // el diálogo de mixto está abierto

      final c = _controladorDe(tester);
      expect(c.medioElegido, ComposicionPago.mixto);

      await _presionarAlt(tester, LogicalKeyboardKey.keyE);
      await tester.pump();

      // La guardia de ModalRoute.isCurrent frena al handler: el diálogo de
      // abajo nunca se entera de este Alt+E.
      expect(c.medioElegido, ComposicionPago.mixto);
      expect(find.text('Pago mixto'), findsOneWidget);
    });

  });

  group('bug real: AltGr no debe disparar los atajos reservados', () {
    testWidgets(
      'AltGr+E (Ctrl+AltRight sintético) NO elige efectivo, a diferencia de Alt+E real',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        final c = _controladorDe(tester);
        expect(c.medioElegido, isNull);

        await _presionarAltGr(tester, LogicalKeyboardKey.keyE);
        expect(c.medioElegido, isNull); // AltGr no cuenta como el atajo

        await _presionarAlt(tester, LogicalKeyboardKey.keyE);
        expect(c.medioElegido, ComposicionPago.efectivo); // el atajo real sí
      },
    );
  });

  group('el catálogo en memoria se refresca al volver de una pantalla pusheada', () {
    testWidgets(
      'un producto cargado mientras Proveedores está abierto aparece en la búsqueda al volver a la venta',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await _navegarA(tester, 'Proveedores');
        expect(
          find.byType(PantallaVenta),
          findsNothing,
        ); // tapada por la ruta de Proveedores

        // Simula lo que hace el modal de "Nuevo producto" de Proveedores:
        // insertar directo en la base, sin pasar por el controlador de venta
        // (que en este momento ni siquiera está montado en el árbol activo).
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Fernet Branca 750ml',
                precioCentavos: const Value(890000),
                stock: const Value(5),
              ),
            );

        await _navegarA(tester, 'Venta');

        // Bug real (arreglado en `_irAProveedores`, `pantalla_venta.dart`): sin
        // el `cargarTodo()` al volver, `_catalogo` seguía siendo el de la
        // apertura de la app y este producto no aparecía hasta un hot restart.
        await tester.enterText(find.byType(TextField).first, 'fernet');
        await tester.pump();

        expect(_enDropdown('Fernet Branca 750ml'), findsOneWidget);
      },
    );

    testWidgets(
      'crear un proveedor Y un producto desde Proveedores, y volver por SU propia barra '
      '(no por back), también refresca el catálogo de la venta',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        // 1920×1080 acá (no los 1366×768 de `_pump`): el modal de "+ Nuevo
        // producto" es alto y a 1366 desborda — ruido de layout ajeno a lo que
        // este test verifica (la recarga del catálogo al volver).
        tester.view.physicalSize = const Size(1920, 1080);
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

        await _navegarA(tester, 'Proveedores');
        expect(find.byType(PantallaVenta), findsNothing);

        // "Nuevo proveedor" está en las acciones de la cabecera de Proveedores (mock v4).
        await tester.tap(find.byKey(const Key('boton_nuevo_proveedor')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('campo_nombre')),
          'Distribuidora Nueva',
        );
        await tester.enterText(find.byKey(const Key('campo_codigo')), 'DN');
        await tester.tap(find.text('Crear proveedor'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('boton_nuevo_producto')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('campo_nombre')),
          'Alfajor Nuevo',
        );
        await tester.enterText(find.byKey(const Key('campo_precio')), '500');
        // Sin stock, no aparece en la búsqueda de Venta (El dueño,
        // 2026-09-06) — este test es sobre el refresco del catálogo, no
        // sobre stock, así que necesita algo de stock para poder
        // encontrarlo después.
        await tester.enterText(find.byKey(const Key('campo_stock')), '5');
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();

        // Volver por la barra lateral DE PROVEEDORES (`EnvolturaConBarraLateral`
        // → `navegarASeccionDeGestion`), no por "atrás" — Proveedores no tiene
        // flecha de volver, así vuelve la app real (El dueño).
        await _navegarA(tester, 'Venta');

        expect(find.byType(PantallaVenta), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'alfajor nuevo');
        await tester.pump();

        expect(_enDropdown('Alfajor Nuevo'), findsOneWidget);
      },
    );

    testWidgets(
      'Bug real (Dueño, 2026-09-05): entrar a Proveedores DESDE OTRA sección de gestión '
      '(no directo desde la venta) también tiene que refrescar el catálogo al volver',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        tester.view.physicalSize = const Size(1920, 1080);
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

        // Venta → Historial (por `_irAHistorial`, que SÍ conoce a
        // `VentaControlador`) → Proveedores (por la barra lateral COMPARTIDA
        // de Historial, `navegarASeccionDeGestion` — este salto no pasa por
        // ninguno de los `_irAX` de `pantalla_venta.dart`, así que ese código
        // no tiene forma de enterarse de que hay que recargar al volver).
        await _navegarA(tester, 'Historial');
        await _navegarA(tester, 'Proveedores');

        // "Nuevo proveedor" está en las acciones de la cabecera de Proveedores (mock v4).
        await tester.tap(find.byKey(const Key('boton_nuevo_proveedor')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('campo_nombre')),
          'Distribuidora Nueva',
        );
        await tester.enterText(find.byKey(const Key('campo_codigo')), 'DN');
        await tester.tap(find.text('Crear proveedor'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('boton_nuevo_producto')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('campo_nombre')),
          'Alfajor Nuevo',
        );
        await tester.enterText(find.byKey(const Key('campo_precio')), '500');
        // Sin stock, no aparece en la búsqueda de Venta (El dueño,
        // 2026-09-06) — este test es sobre el refresco del catálogo, no
        // sobre stock, así que necesita algo de stock para poder
        // encontrarlo después.
        await tester.enterText(find.byKey(const Key('campo_stock')), '5');
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();

        await _navegarA(tester, 'Venta');

        expect(find.byType(PantallaVenta), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'alfajor nuevo');
        await tester.pump();

        expect(_enDropdown('Alfajor Nuevo'), findsOneWidget);
      },
    );
  });
}
