import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;
  late int medioMpId;
  late int cajaNormalId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    cajaNormalId = (await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<int> proveedor(String codigo) async =>
      (await (db.select(db.proveedores)..where((p) => p.codigo.equals(codigo))).getSingle()).id;

  /// Venta de hoy de una línea. En efectivo deja también su movimiento de
  /// caja (de ahí sale la plata del cajón para el ajuste).
  Future<void> vender(int proveedorId, {required int precio, required int costo, bool porMp = false}) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: precio, totalCentavos: precio),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            proveedorIdFoto: Value(proveedorId),
            precioUnitarioCentavos: precio,
            costoUnitarioCentavos: Value(costo),
          ),
        );
    await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: porMp ? medioMpId : medioEfectivoId, montoCentavos: precio),
        );
    if (!porMp) {
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormalId,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              montoCentavos: precio,
              ventaId: Value(ventaId),
            ),
          );
    }
  }

  Future<void> pump(WidgetTester tester, {Size tamanio = const Size(1920, 1080)}) async {
    tester.view.physicalSize = tamanio;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: PantallaSeparaciones(db: db, usuarioId: usuarioId, sesionCajaId: sesionId),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La recarga periódica deja un timer vivo: se desmonta la pantalla antes
  /// de que termine el test.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('sin ventas hoy muestra el estado vacío', (tester) async {
    await pump(tester);
    expect(find.text('Hoy no hay nada para separar'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('tarjetas de caja: cobrado, a separar y te queda, por caja y en total', (tester) async {
    await vender(await proveedor('S'), precio: 100000, costo: 60000);
    await vender(await proveedor('F'), precio: 50000, costo: 30000, porMp: true);
    await pump(tester);

    // Rediseño v4: a separar del cajón y de Mercado Pago, y lo que queda entre las dos cajas.
    expect(find.text(r'$ 600'), findsWidgets); // separar efectivo (y lo que queda en total)
    expect(find.text(r'$ 300'), findsWidgets); // separar Mercado Pago
    expect(find.textContaining(r'Efectivo $ 400 · MP $ 200'), findsOneWidget); // te queda, por caja
    expect(find.textContaining(r'Separaste $ 0 de $ 900'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('una tarjeta por proveedor, de mayor a menor, con la división por caja', (tester) async {
    await vender(await proveedor('F'), precio: 50000, costo: 30000, porMp: true);
    await vender(await proveedor('S'), precio: 100000, costo: 60000);
    await pump(tester);

    final serra = tester.getTopLeft(find.text('Distribuidora'));
    final mazzota = tester.getTopLeft(find.text('Fiambrería'));
    expect(serra.dy, lessThan(mazzota.dy)); // Distribuidora ($600) va antes que Fiambrería ($300)
    expect(find.textContaining(RegExp(r'^A separar ·')), findsNWidgets(2));
    expect(find.byKey(const Key('progreso_separados')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('progreso_separados'))).data, '0 de 2 separados');
    await desmontar(tester);
  });

  testWidgets('tocar la tarjeta la tilda (separa) y tocarla de nuevo la destilda', (tester) async {
    final serra = await proveedor('S');
    await vender(serra, precio: 100000, costo: 60000);
    await pump(tester);

    await tester.tap(find.text('Distribuidora'));
    await tester.pumpAndSettle();
    expect((await (db.select(db.proveedores)..where((p) => p.id.equals(serra))).getSingle()).separadoCentavos, 60000);
    expect(find.textContaining(RegExp(r'^Separado ·')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('progreso_separados'))).data, '1 de 1 separados');

    await tester.tap(find.text('Distribuidora'));
    await tester.pumpAndSettle();
    expect((await (db.select(db.proveedores)..where((p) => p.id.equals(serra))).getSingle()).separadoCentavos, 0);
    expect(find.textContaining(RegExp(r'^A separar ·')), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('"Marcar todo" y "Desmarcar todo"', (tester) async {
    await vender(await proveedor('S'), precio: 100000, costo: 60000);
    await vender(await proveedor('F'), precio: 50000, costo: 30000, porMp: true);
    await pump(tester);

    await tester.tap(find.text('Marcar todo'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('progreso_separados'))).data, '2 de 2 separados');

    await tester.tap(find.text('Desmarcar todo'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('progreso_separados'))).data, '0 de 2 separados');
    await desmontar(tester);
  });

  testWidgets('"Lo vendido" muestra vendido, costo y ganancia, y deja elegir el período', (tester) async {
    await vender(await proveedor('S'), precio: 100000, costo: 60000);
    await pump(tester);

    await tester.tap(find.byKey(const Key('boton_ganancia')));
    await tester.pumpAndSettle();
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Reposición (costo)'), findsOneWidget);
    expect(find.text(r'$ 1.000'), findsWidgets);
    expect(find.text(r'$ 400'), findsWidgets);

    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();
    // (El subtítulo "Este mes · …" ya no se dibuja desde el rediseño v4: el período se ve en la pastilla elegida.)
    expect(find.text('Reposición (costo)'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('tocar "Ver cuáles" muestra qué producto se vendió sin costo', (tester) async {
    await vender(await proveedor('S'), precio: 100000, costo: 60000);
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 26000, totalCentavos: 26000),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Coca Lata',
            proveedorIdFoto: Value(await proveedor('K')),
            cantidad: const Value(1),
            precioUnitarioCentavos: 26000,
          ),
        );
    await pump(tester);

    expect(find.text('Coca Lata'), findsNothing);
    await tester.tap(find.byKey(const Key('aviso_sin_costo')));
    await tester.pumpAndSettle();
    expect(find.text('Coca Lata'), findsOneWidget);
    expect(find.textContaining('Crokas'), findsOneWidget);
    expect(find.textContaining(r'vendido $260'), findsOneWidget);
    await tester.tap(find.text('Después'));
    await tester.pumpAndSettle();
    await desmontar(tester);
  });

  testWidgets('entra sin desbordar en el piso mínimo de 1366×768', (tester) async {
    for (final codigo in ['S', 'F', 'E', 'D', 'K', 'I', 'Z', 'X', 'M']) {
      await vender(await proveedor(codigo), precio: 12345678, costo: 9876543);
    }
    await pump(tester, tamanio: const Size(1366, 768));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('boton_ganancia')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await desmontar(tester);
  });

  group('ganancia desde "Lo vendido" (antes en Reportes, 2026-09-26)', () {
    /// Una venta de Distribuidora de $1.000 (costo $600): ganancia sin revisar $400,
    /// cobrada [efectivo] en efectivo y el resto por MP.
    Future<int> ventaDeProveedor({int efectivo = 100000}) async {
      final serra = await proveedor('S');
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 100000, totalCentavos: 100000),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              proveedorIdFoto: Value(serra),
              precioUnitarioCentavos: 100000,
              costoUnitarioCentavos: const Value(60000),
            ),
          );
      await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: efectivo));
      if (efectivo < 100000) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: 100000 - efectivo));
      }
      return serra;
    }

    Future<void> abrirGananciaDelProveedor(WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('boton_ganancia')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Distribuidora'));
      await tester.pumpAndSettle();
    }

    testWidgets('tocar la tarjeta muestra la ganancia sin revisar; "Retener como colchón" la retiene toda', (tester) async {
      final serra = await ventaDeProveedor();
      await abrirGananciaDelProveedor(tester);

      expect(find.text('Ganancia — Distribuidora'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('ganancia_sin_revisar')), matching: find.text(r'$400')),
        findsOneWidget,
      );
      await tester.tap(find.text('Retener como colchón'));
      await tester.pumpAndSettle();

      final p = await (db.select(db.proveedores)..where((x) => x.id.equals(serra))).getSingle();
      expect(p.colchonReposicionCentavos, 40000);
      expect(p.gananciaRevisadaFecha, isNotNull);
      expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('RETIRO'))).get(), isEmpty);
      await desmontar(tester);
    });

    testWidgets('sin el módulo Retiro de ganancias, tocar la tarjeta no abre nada', (tester) async {
      await ventaDeProveedor();
      addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
      modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.retiroGanancias, activo: false);
      await abrirGananciaDelProveedor(tester);

      expect(find.text('Ganancia — Distribuidora'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('"Retirar ganancia" prellena según cómo se cobró y registra un retiro por medio', (tester) async {
      final serra = await ventaDeProveedor(efectivo: 70000);
      await abrirGananciaDelProveedor(tester);

      await tester.tap(find.text('Retirar ganancia'));
      await tester.pumpAndSettle();
      expect(find.text('Retirar ganancia — Distribuidora'), findsOneWidget);
      final campoEfectivo = tester.widget<TextField>(
        find.descendant(of: find.byKey(const Key('campo_retiro_efectivo')), matching: find.byType(TextField)),
      );
      expect(campoEfectivo.controller!.text, '280'); // 40.000 * 70%
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retirar'));
      await tester.pumpAndSettle();

      final retiros = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('RETIRO'))).get();
      expect({for (final m in retiros) m.medioPagoId: m.montoCentavos}, {null: 28000, medioMpId: 12000});
      final p = await (db.select(db.proveedores)..where((x) => x.id.equals(serra))).getSingle();
      expect(p.colchonReposicionCentavos, 0);
      await desmontar(tester);
    });
  });
}
