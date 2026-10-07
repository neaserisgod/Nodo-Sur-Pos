import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/separaciones_extra_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/separaciones/separaciones_controlador.dart';

import '../helpers/base_para_tests.dart';

/// Lo que se sumó a Caja › Separar del celular (El dueño, 2026-10-07): retirar plata y vendido sin costo, con las reglas de la PC.
void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;
  late int medioMpId;
  late int serra;

  setUp(() async {
    db = baseDeTest();
    usuarioId = (await db.select(db.usuarios).get()).first.id;
    sesionId = await db.into(db.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0));
    medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    serra = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('S'))).getSingle()).id;
  });
  tearDown(() => db.close());

  /// Venta de hoy de Distribuidora ($1.000, costo $600 o sin costo), cobrada [efectivo] en efectivo y el resto por MP.
  Future<void> vender({int efectivo = 100000, int? costo = 60000, String nombre = 'Producto'}) async {
    final ventaId = await db.into(db.ventas).insert(VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 100000, totalCentavos: 100000));
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: nombre,
            proveedorIdFoto: Value(serra),
            precioUnitarioCentavos: 100000,
            costoUnitarioCentavos: Value(costo),
          ),
        );
    await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: efectivo));
    if (efectivo < 100000) await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: 100000 - efectivo));
  }

  Future<SeparacionesControlador> abrir(WidgetTester tester, Future<void> Function(BuildContext, SeparacionesControlador) accion) async {
    final c = SeparacionesControlador(db, usuarioId: usuarioId, sesionCajaId: sesionId);
    await tester.runAsync(c.cargarTodo);
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => accion(context, c), child: const Text('abrir')))),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  testWidgets('"Retirar plata" lista la ganancia sin revisar; retener la deja como colchón', (tester) async {
    await vender();
    await abrir(tester, mostrarRetirarPlataNs);
    expect(find.text('Distribuidora'), findsOneWidget);
    await tester.tap(find.text('Distribuidora'));
    await tester.pumpAndSettle();
    expect(find.text('Ganancia — Distribuidora'), findsOneWidget);

    await tester.tap(find.text('Retener como colchón'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));
    final p = await (db.select(db.proveedores)..where((x) => x.id.equals(serra))).getSingle();
    expect(p.colchonReposicionCentavos, 40000);
    expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('RETIRO'))).get(), isEmpty);
  });

  testWidgets('retirar prellena según cómo se cobró, no deja pasarse de la ganancia, y registra un retiro por medio', (tester) async {
    await vender(efectivo: 70000);
    await abrir(tester, (context, c) => mostrarGananciaProveedorNs(context, c, serra));
    await tester.tap(find.text('Retirar ganancia'));
    await esperar(tester);

    final campos = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(campos[0].controller!.text, '280'); // 40.000 × 70 %
    expect(campos[1].controller!.text, '120');

    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Retirar'));
    await esperar(tester);
    expect(find.textContaining('no pueden superar'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '280');
    await tester.tap(find.text('Retirar'));
    await esperar(tester);
    if (find.text('Retirar igual').evaluate().isNotEmpty) {
      // Con los gastos del mes el retiro puede pasarse de lo retirable: se avisa y se confirma.
      await tester.tap(find.text('Retirar igual'));
      await esperar(tester);
    }
    await tester.pump(const Duration(seconds: 6));

    final retiros = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('RETIRO'))).get();
    expect({for (final m in retiros) m.medioPagoId: m.montoCentavos}, {null: 28000, medioMpId: 12000});
  });

  testWidgets('vendido sin costo: lo muestra y deja cargarle el costo ahí mismo', (tester) async {
    final coca = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Coca Lata', proveedorId: Value(serra), precioCentavos: const Value(100000)));
    await vender(costo: null, nombre: 'Coca Lata');
    await (db.update(db.lineasDeVenta)..where((l) => l.nombreProductoFoto.equals('Coca Lata'))).write(LineasDeVentaCompanion(productoId: Value(coca)));
    final c = await abrir(tester, (context, c) => mostrarSinCostoNs(context, c, desde: c.inicioDeHoy, periodo: 'hoy'));
    await esperar(tester);
    expect(find.text('Coca Lata'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '600');
    await tester.tap(find.text('Guardar costos'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));
    final p = await (db.select(db.productos)..where((x) => x.id.equals(coca))).getSingle();
    expect(p.costoCentavos, 60000);
    expect(c.vendidoSinCostoHoyCentavos, 0, reason: 'la venta toma el costo y la separación se recalcula');
  });
}
