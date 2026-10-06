import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/proveedores/detalle_proveedor.dart';
import 'package:la_plazoleta/ui/proveedores/lista_proveedores.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db, {
  required int usuarioId,
  int? sesionCajaId,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: PantallaProveedores(
        db: db,
        usuarioId: usuarioId,
        sesionCajaId: sesionCajaId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` FUERA del `TextField`
/// (fija, no la flotante de Material) — así que ya no se puede encontrar el
/// campo por su texto de label como antes (`find.widgetWithText`). Cada campo
/// que un test necesita tocar tiene una `Key` propia en el widget que llama.
Finder _campo(String llave) => find.descendant(
  of: find.byKey(Key(llave)),
  matching: find.byType(TextField),
);

/// "+ Nuevo proveedor" es un botón propio del picker (séptima pasada) — ya
/// no hace falta pasar por "Más acciones" para llegar a él desde ahí (esa
/// opción del menú solo existe con `verDetalle` — ver
/// `pantalla_proveedores.dart::_AccionesProveedores`).
Future<void> _abrirNuevoProveedor(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('boton_nuevo_proveedor')));
  await tester.pumpAndSettle();
}

/// Lista de proveedores siempre a la izquierda ("Lenguaje de diseño",
/// 2026-09-26): elegir uno es tocarlo en la lista — el mismo nombre también
/// aparece como título del detalle, por eso se busca dentro de la lista.
Future<void> _entrarAProveedor(WidgetTester tester, String etiqueta) async {
  final lista = find.byType(ListaProveedores);
  final fila = find.descendant(of: lista, matching: find.text(etiqueta));
  // La lista es perezosa (`ListView`): "Sin proveedor" va al final y puede
  // no estar construida todavía.
  await tester.scrollUntilVisible(fila, 200, scrollable: find.descendant(of: lista, matching: find.byType(Scrollable)).last);
  await tester.tap(fila);
  await tester.pumpAndSettle();
}

void main() {
  group('Todos / Sin proveedor / proveedor (fase 13, kit)', () {
    testWidgets('"Todos" es la vista inicial, con las cinco métricas', (
      tester,
    ) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
            ),
          );

      await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);

      // La lista (izquierda) trae "Todos", "Sin proveedor" y cada proveedor
      // real; "Todos" arranca elegido y su detalle ya está a la derecha.
      final lista = find.byType(ListaProveedores);
      expect(find.descendant(of: lista, matching: find.text('Todos')), findsOneWidget);
      expect(find.descendant(of: lista, matching: find.text('Distribuidora')), findsOneWidget);

      final detalle = find.byType(DetalleProveedor);
      expect(find.descendant(of: detalle, matching: find.text('Todos los productos')), findsOneWidget);
      expect(find.descendant(of: detalle, matching: find.text('Stock a precio')), findsOneWidget);
      // "Separado" solo existe con un proveedor real (no hay reposición de
      // "Todos"): ni siquiera se muestra la caja.
      expect(find.descendant(of: detalle, matching: find.text('Separado')), findsNothing);
      expect(find.text('Avanzado'), findsNothing); // solo con un proveedor real
    });

    testWidgets(
      'tocar un proveedor trae sus cinco cifras y habilita "Avanzado"',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');

        expect(find.text('Avanzado'), findsOneWidget);
        final detalle = find.byType(DetalleProveedor);
        expect(
          find.descendant(of: detalle, matching: find.text('Ganancia')),
          findsWidgets, // la cifra del período y la columna de la tabla
        );

        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();

        expect(find.text('Costo real pendiente'), findsOneWidget);
        expect(find.text('Marcar separado'), findsOneWidget);
      },
    );

    testWidgets('"Sin proveedor" solo muestra productos huérfanos', (
      tester,
    ) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
            ),
          );
      final proveedorSId = (await (db.select(
        db.proveedores,
      )..where((p) => p.codigo.equals('S'))).getSingle()).id;
      await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Con proveedor',
              proveedorId: Value(proveedorSId),
            ),
          );
      await db
          .into(db.productos)
          .insert(ProductosCompanion.insert(nombre: 'Huérfano'));

      await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
      await _entrarAProveedor(tester, 'Sin proveedor');

      expect(find.text('Huérfano'), findsOneWidget);
      expect(find.text('Con proveedor'), findsNothing);
      expect(find.text('Avanzado'), findsNothing);
    });

    testWidgets(
      'tocar otro proveedor en la lista cambia el detalle sin salir de la pantalla',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );

        final proveedorSId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle()).id;
        final arcorId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('A'))).getSingle()).id;
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Coca-Cola 500ml',
                proveedorId: Value(proveedorSId),
              ),
            );
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Alfajor Arcor',
                proveedorId: Value(arcorId),
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        expect(find.text('Avanzado'), findsOneWidget); // adentro del detalle

        await _entrarAProveedor(tester, 'Arcor');

        expect(find.text('Avanzado'), findsOneWidget); // otro proveedor real
        expect(find.text('Alfajor Arcor'), findsOneWidget); // productos de Arcor
        expect(find.text('Coca-Cola 500ml'), findsNothing); // ya no los de Distribuidora
        // La lista sigue ahí: se puede volver a Distribuidora de un toque.
        expect(find.byType(ListaProveedores), findsOneWidget);
      },
    );
  });

  group(
    'Separación de fondos por proveedor (Regla 5 extendida, corte = pago)',
    () {
      Future<int> crearProveedorConVenta(
        AppDatabase db, {
        required int usuarioId,
        required int sesionId,
      }) async {
        final proveedorId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle()).id;
        final ventaId = await db
            .into(db.ventas)
            .insert(
              VentasCompanion.insert(
                sesionCajaId: sesionId,
                usuarioId: usuarioId,
                subtotalCentavos: 100000,
                totalCentavos: 100000,
              ),
            );
        await db
            .into(db.lineasDeVenta)
            .insert(
              LineasDeVentaCompanion.insert(
                ventaId: ventaId,
                nombreProductoFoto: 'Producto',
                proveedorIdFoto: Value(proveedorId),
                precioUnitarioCentavos: 100000,
                costoUnitarioCentavos: const Value(60000),
              ),
            );
        return proveedorId;
      }

      testWidgets(
        'separar congela el monto; pagar de menos deja la diferencia en pendiente sin separar',
        (tester) async {
          final db = baseDeTest();
          addTearDown(db.close);
          final usuarioId = await db
              .into(db.usuarios)
              .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
          final sesionId = await db
              .into(db.sesionesDeCaja)
              .insert(
                SesionesDeCajaCompanion.insert(
                  usuarioAbrioId: usuarioId,
                  fondoInicialCentavos: 0,
                ),
              );
          final proveedorId = await crearProveedorConVenta(
            db,
            usuarioId: usuarioId,
            sesionId: sesionId,
          );

          await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
          await _entrarAProveedor(tester, 'Distribuidora');
          await tester.tap(find.text('Avanzado'));
          await tester.pumpAndSettle();

          expect(find.text('Marcar separado'), findsOneWidget);
          await tester.tap(find.text('Marcar separado'));
          await tester.pumpAndSettle();

          expect(find.textContaining('Esperando pago'), findsOneWidget);

          await tester.tap(find.text('Pagar').first);
          await tester.pumpAndSettle();

          await tester.enterText(_campo('campo_monto_pagado'), '400');
          await tester.tap(find.text('Registrar pago').last);
          await tester.pumpAndSettle();

          expect(find.textContaining('Esperando pago'), findsNothing);
          expect(find.text('Marcar separado'), findsOneWidget);

          final movimiento = await (db.select(
            db.movimientosDeCaja,
          )..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).getSingle();
          expect(movimiento.montoCentavos, 40000);

          final proveedor = await (db.select(
            db.proveedores,
          )..where((p) => p.id.equals(proveedorId))).getSingle();
          expect(
            proveedor.pendienteBaseCentavos,
            20000,
          ); // 600 - 400, no se perdió ni se dio por saldado
          expect(proveedor.ultimoPagoFecha, isNotNull);
        },
      );

      testWidgets('el diálogo de pago rechaza un monto mayor a lo separado', (
        tester,
      ) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );
        await crearProveedorConVenta(
          db,
          usuarioId: usuarioId,
          sesionId: sesionId,
        );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marcar separado'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Pagar').first);
        await tester.pumpAndSettle();
        await tester.enterText(_campo('campo_monto_pagado'), '9999');
        await tester.tap(find.text('Registrar pago').last);
        await tester.pumpAndSettle();

        expect(find.text('No puede ser mayor a lo separado'), findsOneWidget);
      });
    },
  );

  group('Nivel 3 — Avanzado', () {
    testWidgets(
      'guarda código, días y activo, y el proveedor desactivado desaparece de la lista',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();

        await tester.enterText(_campo('campo_dia_pedido'), 'Lunes');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        final proveedor = await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle();
        expect(proveedor.diaPedido, 'Lunes');
      },
    );

    testWidgets(
      'un código ya usado por otro proveedor muestra el error, no lo guarda',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();

        await tester.enterText(
          _campo('campo_codigo'),
          'F',
        ); // código de Fiambrería
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Ya hay un proveedor con el código'),
          findsOneWidget,
        );
      },
    );
  });

  group('Editar un producto (Modal — absorbe la vieja pantalla Productos)', () {
    testWidgets(
      'tocar una fila de la tabla abre el modal y guarda el precio nuevo',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );
        final proveedorSId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle()).id;
        final productoId = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Coca-Cola',
                proveedorId: Value(proveedorSId),
                precioCentavos: const Value(150000),
                costoCentavos: const Value(90000),
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.text('Coca-Cola'));
        await tester.pumpAndSettle();

        expect(find.text('Editar producto'), findsOneWidget);
        await tester.enterText(_campo('campo_precio'), '1700');
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();

        final producto = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(productoId))).getSingle();
        expect(producto.precioCentavos, 170000);
      },
    );

    testWidgets(
      '"+ Nuevo producto" da de alta uno con el proveedor de la vista actual preseleccionado',
      (tester) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );
        final proveedorSId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle()).id;

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.byKey(const Key('boton_nuevo_producto')));
        await tester.pumpAndSettle();

        // El botón de atrás y el título del modal.
        expect(find.text('Nuevo producto'), findsNWidgets(2));
        await tester.enterText(_campo('campo_nombre'), 'Alfajor');
        await tester.enterText(_campo('campo_precio'), '500');
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();

        final producto = await (db.select(
          db.productos,
        )..where((p) => p.nombre.equals('Alfajor'))).getSingle();
        expect(producto.proveedorId, proveedorSId);
        expect(producto.precioCentavos, 50000);
      },
    );
  });

  group(
    'Editar y agregar proveedores (Dueño: "se debe poder editar y agregar los proveedores")',
    () {
      testWidgets('"Avanzado" también permite cambiar el nombre', (
        tester,
      ) async {
        final db = baseDeTest();
        addTearDown(db.close);
        final usuarioId = await db
            .into(db.usuarios)
            .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
        final sesionId = await db
            .into(db.sesionesDeCaja)
            .insert(
              SesionesDeCajaCompanion.insert(
                usuarioAbrioId: usuarioId,
                fondoInicialCentavos: 0,
              ),
            );

        await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
        await _entrarAProveedor(tester, 'Distribuidora');
        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();

        await tester.enterText(_campo('campo_nombre'), 'Distribuidora Almacén');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        final proveedor = await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('S'))).getSingle();
        expect(proveedor.nombre, 'Distribuidora Almacén');
        expect(
          find.text('Distribuidora Almacén'),
          findsWidgets,
        ); // nombre nuevo reflejado en la lista/detalle
      });

      testWidgets(
        '"+ Nuevo proveedor" da de alta uno, lo selecciona y aparece en la lista',
        (tester) async {
          final db = baseDeTest();
          addTearDown(db.close);
          final usuarioId = await db
              .into(db.usuarios)
              .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
          final sesionId = await db
              .into(db.sesionesDeCaja)
              .insert(
                SesionesDeCajaCompanion.insert(
                  usuarioAbrioId: usuarioId,
                  fondoInicialCentavos: 0,
                ),
              );

          await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
          await _abrirNuevoProveedor(tester);

          await tester.enterText(_campo('campo_nombre'), 'Distribuidora Nueva');
          await tester.enterText(_campo('campo_codigo'), 'DN');
          await tester.tap(find.text('Crear proveedor'));
          await tester.pumpAndSettle();

          final proveedor = await (db.select(
            db.proveedores,
          )..where((p) => p.codigo.equals('DN'))).getSingle();
          expect(proveedor.nombre, 'Distribuidora Nueva');
          expect(proveedor.activo, isTrue);
          // Sin hot restart ni nada manual: recarga y selecciona el nuevo solo.
          expect(find.text('Distribuidora Nueva'), findsWidgets);
          expect(find.text('Avanzado'), findsOneWidget);
        },
      );

      testWidgets(
        'crear un proveedor con un código repetido muestra el error, no lo crea',
        (tester) async {
          final db = baseDeTest();
          addTearDown(db.close);
          final usuarioId = await db
              .into(db.usuarios)
              .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
          final sesionId = await db
              .into(db.sesionesDeCaja)
              .insert(
                SesionesDeCajaCompanion.insert(
                  usuarioAbrioId: usuarioId,
                  fondoInicialCentavos: 0,
                ),
              );

          await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);
          await _abrirNuevoProveedor(tester);

          await tester.enterText(_campo('campo_nombre'), 'Otro Distribuidora');
          await tester.enterText(_campo('campo_codigo'), 'S'); // ya existe
          await tester.tap(find.text('Crear proveedor'));
          await tester.pumpAndSettle();

          expect(
            find.text('Ya hay un proveedor con el código "S"'),
            findsOneWidget,
          );
          final cantidad = await (db.select(
            db.proveedores,
          )..where((p) => p.nombre.equals('Otro Distribuidora'))).get();
          expect(cantidad, isEmpty);
        },
      );
    },
  );

  group('Separar dividido entre cajón y Mercado Pago (Dueño, 2026-09-26)', () {
    /// Sesión abierta con dos ventas de Distribuidora (proveedor común): una en
    /// efectivo (costo $600) y otra por QR (costo $300).
    Future<({int usuarioId, int sesionId})> preparar(AppDatabase db) async {
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final serra = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle()).id;
      final efectivo = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      final mp = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      for (final (precio, costo, medio) in [(100000, 60000, efectivo), (50000, 30000, mp)]) {
        final ventaId = await db.into(db.ventas).insert(
              VentasCompanion.insert(
                sesionCajaId: sesionId,
                usuarioId: usuarioId,
                subtotalCentavos: precio,
                totalCentavos: precio,
              ),
            );
        await db.into(db.lineasDeVenta).insert(
              LineasDeVentaCompanion.insert(
                ventaId: ventaId,
                nombreProductoFoto: 'Producto',
                proveedorIdFoto: Value(serra),
                precioUnitarioCentavos: precio,
                costoUnitarioCentavos: Value(costo),
              ),
            );
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medio, montoCentavos: precio));
      }
      return (usuarioId: usuarioId, sesionId: sesionId);
    }

    testWidgets('"Avanzado" muestra de dónde sale lo que hay que separar', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora');
      await tester.tap(find.text('Avanzado'));
      await tester.pumpAndSettle();

      expect(find.text('   del cajón'), findsOneWidget);
      // $600 también figura como "Separado" en las cifras de atrás.
      expect(find.text('\$600'), findsWidgets);
      expect(find.text('   de Mercado Pago'), findsOneWidget);
      expect(find.text('\$300'), findsOneWidget);
    });

    testWidgets('pagar trae los dos montos prellenados y graba un movimiento por cada medio', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora');
      await tester.tap(find.text('Avanzado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar separado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagar').first);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_campo('campo_monto_pagado')).controller!.text, '600');
      expect(tester.widget<TextField>(_campo('campo_monto_pagado_mp')).controller!.text, '300');
      await tester.tap(find.text('Registrar pago').last);
      await tester.pumpAndSettle();

      final mp = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).get();
      expect({for (final m in movimientos) m.medioPagoId: m.montoCentavos}, {null: 60000, mp: 30000});
    });

    testWidgets('pagar más de lo separado entre los dos campos se avisa y no se paga', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora');
      await tester.tap(find.text('Avanzado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar separado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagar').first);
      await tester.pumpAndSettle();

      await tester.enterText(_campo('campo_monto_pagado_mp'), '301');
      await tester.tap(find.text('Registrar pago').last);
      await tester.pumpAndSettle();

      expect(find.text('No puede ser mayor a lo separado'), findsOneWidget);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });

    testWidgets('Distribuidora de Cigarrillos muestra "Ver lata" sin separar/pagar ni medio de pago', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora de Cigarrillos');

      expect(find.text('Avanzado'), findsNothing);
      await tester.tap(find.text('Ver lata'));
      await tester.pumpAndSettle();

      expect(find.text('Saldo de la lata'), findsOneWidget);
      expect(find.text('Marcar separado'), findsNothing);
      expect(find.text('Costo real pendiente'), findsNothing);
      expect(find.text('Medio de pago'), findsNothing);
      expect(find.byKey(const Key('campo_nombre')), findsOneWidget);
    });

    testWidgets('la caja aparte es una propiedad del proveedor, no su código: cualquiera puede tenerla', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);
      // Distribuidora de Cigarrillos deja de ser especial; otro proveedor pasa a serlo.
      await db.customStatement("UPDATE proveedores SET caja_aparte = 0 WHERE codigo = 'SC'");
      await db.customStatement("UPDATE proveedores SET caja_aparte = 1 WHERE codigo = 'A'");

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora de Cigarrillos');
      expect(find.text('Avanzado'), findsOneWidget);
      expect(find.text('Ver lata'), findsNothing);

      await _entrarAProveedor(tester, 'Arcor');
      expect(find.text('Ver lata'), findsOneWidget);
      expect(find.text('Avanzado'), findsNothing);
    });

    testWidgets('en Avanzado se marca y desmarca la caja aparte, y se guarda', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);

      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Fiambrería');
      await tester.tap(find.text('Avanzado'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('interruptor_caja_aparte')), findsOneWidget);
      expect(find.text('Medio de pago'), findsOneWidget);

      await tester.tap(find.byKey(const Key('interruptor_caja_aparte')));
      await tester.pumpAndSettle();
      // Con caja aparte cobra solo en efectivo: ya no se elige medio de pago.
      expect(find.text('Medio de pago'), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final f = await (db.select(db.proveedores)..where((x) => x.codigo.equals('F'))).getSingle();
      expect(f.cajaAparte, isTrue);
      expect(f.medioPago, 'Efectivo');
      expect(find.text('Ver lata'), findsOneWidget);
    });

    testWidgets('con los módulos Promos y Comparador apagados, no se ofrecen sus botones', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final p = await preparar(db);
      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);

      expect(find.text('Promos'), findsOneWidget);
      expect(find.text('Comparar precios'), findsOneWidget);

      modulosActuales.value = ModulosNegocio.todosActivos
          .conModulo(Modulo.promos, activo: false)
          .conModulo(Modulo.compararPrecios, activo: false);
      addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
      await tester.pumpAndSettle();
      expect(find.text('Promos'), findsNothing);
      expect(find.text('Comparar precios'), findsNothing);
      expect(find.text('Importar CSV'), findsOneWidget);
    });

    testWidgets('en "Nuevo producto", sin los módulos Pesables y Caja aparte no se ofrece ser pesable ni cigarrillo', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
      final p = await preparar(db);
      await _pump(tester, db, usuarioId: p.usuarioId, sesionCajaId: p.sesionId);
      await _entrarAProveedor(tester, 'Distribuidora');

      await tester.tap(find.byKey(const Key('boton_nuevo_producto')));
      await tester.pumpAndSettle();
      expect(find.text('Es pesable (se carga por gramos)'), findsOneWidget);
      expect(find.text('Cigarrillo'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      modulosActuales.value = ModulosNegocio.todosActivos
          .conModulo(Modulo.pesables, activo: false)
          .conModulo(Modulo.cajaAparte, activo: false);
      await tester.tap(find.byKey(const Key('boton_nuevo_producto')));
      await tester.pumpAndSettle();
      expect(find.text('Es pesable (se carga por gramos)'), findsNothing);
      expect(find.text('Cigarrillo'), findsNothing);
      expect(find.text('Categoría'), findsOneWidget);
    });
  });
}
