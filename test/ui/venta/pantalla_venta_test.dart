// Tests de widget de los tres puntos críticos de la Fase 3, simulando
// teclado y mouse de verdad (no solo llamando métodos del controlador).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/tema/tokens.dart';
import 'package:la_plazoleta/ui/venta/columna_carrito.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';
import 'package:la_plazoleta/ui/tema/iconos.dart';
import '../../helpers/base_para_tests.dart';

Future<AppDatabase> _crearBaseConSesion() async {
  final db = baseDeTest();
  final usuarioId = await db
      .into(db.usuarios)
      .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: 'Coca-Cola 500ml',
          precioCentavos: const Value(112000),
          costoCentavos: const Value(80000),
          stock: const Value(20),
        ),
      );
  await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: 'Marlboro',
          precioCentavos: const Value(500000),
          tipoCigarrillo: const Value('atado'),
          stock: const Value(20),
        ),
      );
  return db;
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  // El viewport de test por defecto (800x600) es más chico que el piso
  // mínimo de la app (1366x768 desde la fase 13) — con eso, el layout de
  // tres columnas (más la barra lateral) nunca se ejercita en un ancho
  // real. Se fija acá al piso (`DISENO.md`, simulador de resolución).
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

/// Acceso directo al controlador para "elegir el canal" sin pasar por el
/// handler de teclado — más corto en tests que solo verifican recargo o
/// descuento y no tienen nada que ver con Alt+Q/Alt+D en sí.
VentaControlador _controladorDe(WidgetTester tester) {
  final elemento = tester.element(find.byType(Scaffold).first);
  return Provider.of<VentaControlador>(elemento, listen: false);
}

/// Desde el rediseño 2026-09-25 (segunda pasada) el mismo nombre de
/// producto puede aparecer DOS veces a la vez: como línea del carrito y
/// como tile permanente de `RejillaProductos` (la grilla navegable) —
/// `find.text` suelto ya no alcanza para "¿está en el carrito?". Acota la
/// búsqueda al `ColumnaCarrito`, el único lugar que estos tests quieren
/// mirar.
Finder _enElCarrito(String texto) =>
    find.descendant(of: find.byType(ColumnaCarrito), matching: find.text(texto));

/// Mismo motivo: acota al dropdown de resultados de la barra de búsqueda,
/// que también puede coincidir con un tile de la grilla.
Finder _enDropdown(String texto) => find.descendant(
  of: find.byKey(const Key('dropdown_resultados_busqueda')),
  matching: find.text(texto),
);

void main() {
  group('punto crítico #1 — el campo único nunca pierde el foco', () {
    testWidgets('tocar una fila del dropdown deja el foco en el campo único', (
      tester,
    ) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      await _pump(tester, db);

      await tester.enterText(find.byType(TextField).first, 'coca');
      await tester.pump();
      await tester.tap(find.text('Coca-Cola 500ml').first);
      await tester.pump();

      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.focusNode!.hasFocus, true);
    });

    testWidgets('elegir un medio de pago deja el foco en el campo único', (
      tester,
    ) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      await _pump(tester, db);

      await tester.enterText(find.byType(TextField).first, 'coca');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.textContaining('Efectivo').first);
      await tester.pump();

      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.focusNode!.hasFocus, true);
    });
  });

  group('punto crítico #2 — el recargo se recalcula al cambiar el medio', () {
    testWidgets(
      'cigarrillos + Mercado Pago muestra el recargo; volver a efectivo lo saca',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'marlboro');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Directo al controlador — esto es sobre el recargo, no sobre el
        // atajo en sí.
        _controladorDe(tester).elegirCanalDirecto('qr');
        await tester.pump();
        expect(find.textContaining('Recargo QR'), findsOneWidget);

        await _presionarAlt(tester, LogicalKeyboardKey.keyE);
        expect(find.textContaining('Recargo QR'), findsNothing);
      },
    );
  });

  group(
    'Alt+Q/Alt+D eligen el canal nada más — dos pasos de nuevo '
    '(Bruno, 2026-09-08: "necesito cobro manual... no hay más modal para '
    'seleccionarlo", revierte el paso único de la fase 12)',
    () {
      testWidgets(
        'Alt+Q con un producto en el carrito elige el canal pero no abre nada todavía',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          await _presionarAlt(tester, LogicalKeyboardKey.keyQ);
          await tester.pump();

          expect(find.text('Cobrar por QR'), findsNothing);
          expect(
            _controladorDe(tester).canalElegido,
            'qr',
          );
        },
      );

      testWidgets('Alt+D hace lo mismo para Débito', (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        await _presionarAlt(tester, LogicalKeyboardKey.keyD);
        await tester.pump();

        expect(find.text('Cobrar por Débito'), findsNothing);
        expect(_controladorDe(tester).canalElegido, 'debit_card');
      });

      testWidgets(
        'Enter con el campo vacío, después de Alt+Q, recién ahí abre el diálogo de Point',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          await _presionarAlt(tester, LogicalKeyboardKey.keyQ);
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          // Sin access token/terminal configurados en esta base de test —
          // el diálogo se abre igual, y de una muestra el error claro en
          // vez de quedarse solo esperando a que alguien apriete "Cobrar".
          expect(find.text('Cobrar por QR'), findsOneWidget);
          expect(
            find.textContaining('Configurá el access token'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'con el carrito vacío, Alt+Q no rompe nada',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await _presionarAlt(tester, LogicalKeyboardKey.keyQ);
          await tester.pump();

          expect(find.text('Cobrar por QR'), findsNothing);
        },
      );
    },
  );

  group(
    'Alt+M cobra a mano, sin pasar por la terminal Point '
    '(Bruno, 2026-09-08: "necesito cobro manual en el desktop")',
    () {
      testWidgets(
        'con QR ya elegido, Alt+M graba la venta directo sin abrir el diálogo de Point',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          await _presionarAlt(tester, LogicalKeyboardKey.keyQ);
          await tester.pump();
          await _presionarAlt(tester, LogicalKeyboardKey.keyM);
          await tester.pumpAndSettle();

          expect(find.text('Cobrar por QR'), findsNothing);
          final ventas = await db.select(db.ventas).get();
          expect(ventas, hasLength(1));
          expect(_enElCarrito('Coca-Cola 500ml'), findsNothing); // el carrito se vació
        },
      );

      testWidgets(
        'sin ningún canal elegido, Alt+M no hace nada',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          await _presionarAlt(tester, LogicalKeyboardKey.keyM);
          await tester.pumpAndSettle();

          final ventas = await db.select(db.ventas).get();
          expect(ventas, isEmpty);
          expect(_enElCarrito('Coca-Cola 500ml'), findsOneWidget);
        },
      );
    },
  );

  group(
    'punto crítico #3 — Enter hace una sola cosa por vez, sin ambigüedad',
    () {
      testWidgets(
        'Enter con el dropdown mostrando una coincidencia: agrega esa línea',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          expect(
            _enElCarrito('Coca-Cola 500ml'),
            findsOneWidget,
          ); // ahora en el carrito
          expect(find.byType(TextField).evaluate().first, isNotNull);
          final campo = tester.widget<TextField>(find.byType(TextField).first);
          expect(campo.controller!.text, ''); // el campo quedó limpio
        },
      );

      testWidgets(
        'Enter con el campo vacío y un medio elegido: cobra la venta',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          await _presionarAlt(tester, LogicalKeyboardKey.keyE);

          // Campo vacío: el mismo Enter que agregaría un producto, ahora cobra.
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          final ventas = await db.select(db.ventas).get();
          expect(ventas, hasLength(1));
          expect(
            _enElCarrito('Coca-Cola 500ml'),
            findsNothing,
          ); // el carrito se vació
        },
      );

      testWidgets(
        'Enter con el campo vacío y SIN medio elegido: no cobra nada',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          // Sin Alt+E/Q/X todavía.
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          final ventas = await db.select(db.ventas).get();
          expect(ventas, isEmpty);
          expect(
            _enElCarrito('Coca-Cola 500ml'),
            findsOneWidget,
          ); // sigue en el carrito
        },
      );
    },
  );

  group(
    'Eliminar del carrito con el ícono de tacho (reemplaza a Backspace) y Escape',
    () {
      testWidgets(
        'tocar el tacho de una línea la saca del carrito (Bruno, 2026-09-06: "con mouse para seleccionar el producto a eliminar")',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          expect(_enElCarrito('Coca-Cola 500ml'), findsOneWidget);

          // Ya no hay atajo de teclado para esto — Backspace con el campo
          // vacío no hace nada (se sacó a propósito).
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(_enElCarrito('Coca-Cola 500ml'), findsOneWidget);

          await tester.tap(find.byIcon(IconosPlazoleta.deleteOutline));
          await tester.pump();

          expect(_enElCarrito('Coca-Cola 500ml'), findsNothing);
        },
      );

      testWidgets('el tacho elimina la línea correcta, no siempre la última', (
        tester,
      ) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'marlboro');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(_enElCarrito('Coca-Cola 500ml'), findsOneWidget);
        expect(_enElCarrito('Marlboro'), findsOneWidget);

        // Dos líneas, dos tachos — se toca el de la primera (Coca-Cola).
        await tester.tap(find.byIcon(IconosPlazoleta.deleteOutline).first);
        await tester.pump();

        expect(_enElCarrito('Coca-Cola 500ml'), findsNothing);
        expect(_enElCarrito('Marlboro'), findsOneWidget); // el Marlboro sigue
      });

      testWidgets(
        'los botones "−"/"+" ajustan la cantidad de una línea por unidad',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          // 1920×1080, no el piso de `_pump`: los botones "−"/"+" se
          // esconden por debajo de cierto ancho de columna (ver
          // `LayoutBuilder` en `columna_carrito.dart`) — a 1366×768 con la
          // barra desplegada no entran.
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

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          expect(find.text('x1'), findsOneWidget);

          await tester.tap(find.byIcon(IconosPlazoleta.add));
          await tester.pump();
          expect(find.text('x2'), findsOneWidget);

          await tester.tap(find.byIcon(IconosPlazoleta.remove));
          await tester.pump();
          expect(find.text('x1'), findsOneWidget);

          // En 1, "−" saca la línea entera.
          await tester.tap(find.byIcon(IconosPlazoleta.remove));
          await tester.pump();
          expect(_enElCarrito('Coca-Cola 500ml'), findsNothing);
        },
      );

      testWidgets(
        'doble clic en la cantidad abre el diálogo para tipear el valor exacto',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          // `onDoubleTap` no tiene helper propio en `WidgetTester`: dos
          // taps rápidos sobre el mismo punto.
          await tester.tap(find.text('x1'));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.text('x1'));
          await tester.pumpAndSettle();

          expect(find.text('Cambiar cantidad'), findsOneWidget);
          await tester.enterText(find.byKey(const Key('campo_cantidad')), '12');
          await tester.tap(find.text('Listo'));
          await tester.pumpAndSettle();

          expect(find.text('x12'), findsOneWidget);
        },
      );

      testWidgets('Escape cancela la venta entera', (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await _presionarAlt(tester, LogicalKeyboardKey.keyE);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(_enElCarrito('Coca-Cola 500ml'), findsNothing);
        expect(
          find.textContaining('Efectivo').first,
          findsOneWidget,
        ); // el botón sigue, pero ya no seleccionado
      });
    },
  );

  group('atajo de vuelto (fase 8)', () {
    testWidgets('sin configurar, Alt+C no agrega nada', (tester) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      await _pump(tester, db);

      final carritoAntes = _controladorDe(tester).carrito.length;
      await _presionarAlt(tester, LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(_controladorDe(tester).carrito, hasLength(carritoAntes));
    });

    testWidgets('configurado, Alt+C lo agrega al carrito', (tester) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      final carameloId = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Caramelo',
              precioCentavos: const Value(500),
              stock: const Value(100),
            ),
          );
      await (db.update(db.configuracionNegocioTabla)).write(
        ConfiguracionNegocioTablaCompanion(productoVueltoId: Value(carameloId)),
      );

      await _pump(tester, db);

      await _presionarAlt(tester, LogicalKeyboardKey.keyC);
      await tester.pump();

      expect(_enElCarrito('Caramelo'), findsOneWidget);
    });
  });

  group(
    'fila del dropdown (bug: pesables mostraban "\$8.500,00/kg" partido en dos líneas)',
    () {
      Future<AppDatabase> crearBaseConQueso() async {
        final db = await _crearBaseConSesion();
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso cremoso',
                esPesable: const Value(true),
                precioPorKiloCentavos: const Value(850000),
                stockGramos: const Value(3200),
              ),
            );
        return db;
      }

      testWidgets(
        'sin gramos escritos: nombre completo, stock disponible y precio por kilo (nunca partido)',
        (tester) async {
          final db = await crearBaseConQueso();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'queso');
          await tester.pump();

          expect(
            _enDropdown('Queso cremoso'),
            findsOneWidget,
          ); // el nombre entero, sin truncar
          expect(
            find.text('3200 g'),
            findsOneWidget,
          ); // stock disponible, la columna del medio
          // "/kg" es parte del mismo texto que el monto, nunca un widget aparte
          // (bug real, ver TRAMPAS.md) — la grilla también puede mostrar la
          // misma tarifa para este producto, así que se acota al dropdown.
          expect(
            find.descendant(
              of: find.byKey(const Key('dropdown_resultados_busqueda')),
              matching: find.textContaining('8.500/kg'),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'con gramos escritos: el precio es el subtotal calculado, el stock sigue siendo el disponible',
        (tester) async {
          final db = await crearBaseConQueso();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, '200 queso');
          await tester.pump();

          // El stock que se muestra es lo que HAY, no lo que se está por agregar
          // — sigue siendo 3200 g, los 200 escritos no le restan nada todavía
          // (eso pasa recién al confirmar la línea).
          expect(find.text('3200 g'), findsOneWidget);
          // subtotalPesable(850000, 200) = 170000 centavos = $1.700 — nunca a mano.
          expect(find.textContaining('1.700'), findsOneWidget);
        },
      );

      testWidgets(
        'stock en 0: ya no aparece en la búsqueda por nombre (Bruno, 2026-09-06: "si no hay stock, no aparece en ventas")',
        (tester) async {
          // Revierte a propósito la "corrección post-revisión" anterior
          // (Regla 8, "se vende igual, se marca en rojo en el carrito") — ver
          // TRAMPAS.md para el pedido explícito y sus efectos secundarios.
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await db
              .into(db.productos)
              .insert(
                ProductosCompanion.insert(
                  nombre: 'Queso cremoso',
                  esPesable: const Value(true),
                  precioPorKiloCentavos: const Value(850000),
                  stockGramos: const Value(0),
                ),
              );
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'queso');
          await tester.pump();

          expect(find.text('Queso cremoso'), findsNothing);
          expect(
            find.text('Sin coincidencias'),
            findsOneWidget,
          ); // no hay otro "queso" cargado
        },
      );

      testWidgets(
        'stock en 0 pero código de barras conocido: avisa que ya existe, no ofrece darlo de alta de nuevo',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await db
              .into(db.productos)
              .insert(
                ProductosCompanion.insert(
                  nombre: 'Queso cremoso',
                  codigoBarras: const Value('7790001112223'),
                  esPesable: const Value(true),
                  precioPorKiloCentavos: const Value(850000),
                  stockGramos: const Value(0),
                ),
              );
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, '7790001112223');
          await tester.pump();

          expect(find.text('Queso cremoso'), findsOneWidget);
          expect(find.text('Sin stock — no se puede vender'), findsOneWidget);
          expect(
            find.text('Sin coincidencias'),
            findsNothing,
          ); // no es un producto nuevo
          expect(
            find.text('Enter para dar de alta este producto'),
            findsNothing,
          );
        },
      );
    },
  );

  group(
    'acuse de cobro (bug: cobrar no daba ninguna señal de que la venta entró)',
    () {
      testWidgets(
        'tras cobrar, el carrito vacío muestra número de venta y total',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          await _presionarAlt(tester, LogicalKeyboardKey.keyE);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(find.text('El carrito está vacío'), findsNothing);
          expect(find.textContaining('Venta #1 cobrada'), findsOneWidget);
        },
      );

      testWidgets(
        'el acuse desaparece solo, sin timer, en cuanto entra la próxima línea',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          await _presionarAlt(tester, LogicalKeyboardKey.keyE);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(find.textContaining('cobrada'), findsOneWidget);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          expect(find.textContaining('cobrada'), findsNothing);
        },
      );
    },
  );

  group(
    '"Varios" por búsqueda (bug ítem 4: escribir "varios" y elegirlo del dropdown crasheaba)',
    () {
      testWidgets(
        'Enter sobre "Varios" en el dropdown abre el mismo diálogo de monto que Alt+V',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'varios');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          // El diálogo de monto está abierto (mismo que Alt+V), no un crash.
          expect(find.text('Un producto que no está cargado'), findsOneWidget);

          await tester.enterText(
            find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first,
            '500',
          );
          await tester.tap(find.text('Agregar al ticket'));
          await tester.pumpAndSettle();

          // Quedó en el carrito, con el monto cargado, y sin la marca de stock
          // en rojo (Regla 8 no le aplica: "Varios" nunca tiene stock real).
          expect(find.text('\$500'), findsOneWidget);
          final nombreEnCarrito = tester.widget<Text>(find.text('Varios'));
          final colores = TemaPlazoleta.oscuro.extension<ColoresPlazoleta>()!;
          expect(nombreEnCarrito.style?.color, isNot(colores.error));
        },
      );

      testWidgets(
        'tocar "Varios" desde el dropdown con el mouse también abre el diálogo de monto',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'varios');
          await tester.pump();
          await tester.tap(find.text('Varios').first);
          await tester.pumpAndSettle();

          expect(find.text('Un producto que no está cargado'), findsOneWidget);
        },
      );
    },
  );

  group(
    'avisos que reemplazan el silencio (ítem 4: indistinguible de que la app se colgó)',
    () {
      testWidgets(
        'un pesable sin precio por kilo avisa en la búsqueda, no crashea',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await db
              .into(db.productos)
              .insert(
                ProductosCompanion.insert(
                  nombre: 'Jamón cocido',
                  esPesable: const Value(true),
                  stockGramos: const Value(1000),
                ),
              );
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, '200 jamon');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          expect(find.textContaining('precio por kilo'), findsOneWidget);
          expect(
            find.text('El carrito está vacío'),
            findsOneWidget,
          ); // no entró al carrito
        },
      );

      testWidgets(
        'Enter con el campo vacío y sin medio elegido avisa, no queda en silencio',
        (tester) async {
          final db = await _crearBaseConSesion();
          addTearDown(db.close);
          await _pump(tester, db);

          await tester.enterText(find.byType(TextField).first, 'coca');
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();

          // Campo vacío, sin medio elegido todavía.
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(find.textContaining('Elegí un medio de pago'), findsOneWidget);
        },
      );
    },
  );

  group('descuento en la columna de cobro (Regla 17 generalizada)', () {
    testWidgets(
      'tipear un porcentaje descuenta del total en vivo, con el "%" elegido',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        // Virtual, no efectivo: en efectivo el paso de redondeo por
        // default ($100) taparía la cuenta del descuento — virtual nunca
        // redondea (Regla 2), así el total sigue siendo exactamente lo
        // esperado. Directo al controlador — esto es sobre el descuento,
        // no sobre el atajo en sí.
        _controladorDe(tester).elegirCanalDirecto('qr');
        await tester.pump();

        // Remake de disposición (2026-09-19): el descuento pasó de un
        // bloque siempre visible a un ícono que abre un modal (mismo
        // criterio que la companion) — hay que abrirlo antes de tocar el
        // toggle $/% o el campo.
        await tester.tap(find.byIcon(IconosPlazoleta.sellOutlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('%'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('campo_descuento')), '10');
        await tester.pump();

        // Coca-Cola 500ml: $1.120. 10% de descuento = $112 → $1.008.
        expect(find.textContaining('1.008'), findsOneWidget);
        // Remake de disposición (2026-09-19): el desglose pasó de líneas
        // separadas ("Descuento: -$X") a una sola línea compacta unida
        // por " · " ("Descuento -$X"), mismo criterio que la tarjeta del
        // total de la companion.
        expect(find.textContaining('Descuento -\$112'), findsOneWidget);
      },
    );

    testWidgets('cobrar limpia el campo de descuento para la próxima venta', (
      tester,
    ) async {
      final db = await _crearBaseConSesion();
      addTearDown(db.close);
      await _pump(tester, db);

      await tester.enterText(find.byType(TextField).first, 'coca');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await _presionarAlt(tester, LogicalKeyboardKey.keyE);

      // Remake de disposición (2026-09-19): el descuento vive ahora en un
      // modal (ícono en la tarjeta del total) — que ESE modal cargue bien
      // el campo ya lo cubre el test de arriba; acá lo que importa es que
      // "Cobrar" lo limpia, así que se carga el controller directo en vez
      // de manejar la apertura/cierre del modal de nuevo.
      _controladorDe(tester).campoDescuentoCtrl.text = '100';
      await tester.pump();

      // Botón "Cobrar", no Enter en el campo único: el campo de descuento
      // no tiene el foco acá, pero Enter en el campo único de todos modos
      // cobra directo — usar el botón deja esto más explícito.
      await tester.tap(find.text('Cobrar'));
      await tester.pumpAndSettle();

      expect(_controladorDe(tester).campoDescuentoCtrl.text, '');
    });
  });

  group('bug real: Mixto que termina en efectivo/virtual puro no cobraba', () {
    testWidgets(
      'confirmar el monto mixto por el total entero (efectivo puro) cobra con un solo Cobrar',
      (tester) async {
        final db = await _crearBaseConSesion();
        addTearDown(db.close);
        await _pump(tester, db);

        await tester.enterText(find.byType(TextField).first, 'coca');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        // Alt+X abre el diálogo de Mixto.
        await _presionarAlt(tester, LogicalKeyboardKey.keyX);
        await tester.pumpAndSettle();

        // El total real que muestra el diálogo (Coca-Cola $1.120, redondeado
        // hacia arriba al paso de $100 default de un pago con parte en
        // efectivo — Regla 2 — así que NO es simplemente $1.120). El cliente
        // termina pagando ese total entero en efectivo, así que
        // `confirmarMixto` reclasifica el medio a efectivo puro
        // (`clasificarComposicion`) y deja `montoEfectivoMixtoCentavos` en
        // null a propósito.
        final totalCentavos = _controladorDe(tester).resultado!.totalCentavos;
        expect(totalCentavos % 100, 0); // siempre pesos enteros en centavos
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          (totalCentavos ~/ 100).toString(),
        );
        await tester.tap(find.text('Cobrar mixto'));
        await tester.pumpAndSettle();

        expect(_controladorDe(tester).medioElegido, ComposicionPago.efectivo);
        expect(_controladorDe(tester).montoEfectivoMixtoCentavos, isNull);

        // Bug real: `_cobrar` (columna_cobro.dart) chequeaba solo
        // `montoEfectivoMixtoCentavos == null` para decidir si el diálogo se
        // había cancelado, y ese chequeo también daba `true` en este caso
        // (efectivo puro, sin parte mixta) — un solo toque de "Cobrar" no
        // hacía nada, el cajero tenía que tocarlo dos veces sin que nada en
        // pantalla avisara por qué.
        await tester.tap(find.text('Cobrar'));
        await tester.pumpAndSettle();

        expect(_controladorDe(tester).carrito, isEmpty);
        expect(_controladorDe(tester).medioElegido, isNull);

        final cantidadVentas = await (db.selectOnly(db.ventas)
              ..addColumns([db.ventas.id.count()]))
            .map((row) => row.read(db.ventas.id.count()))
            .getSingle();
        expect(cantidadVentas, 1);
      },
    );
  });
}
