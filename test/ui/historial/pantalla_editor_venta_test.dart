import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/historial/pantalla_editor_venta.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, {required int ventaId, required int usuarioId}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaEditorVenta(db: db, ventaId: ventaId, usuarioId: usuarioId)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cambiar la cantidad de una línea actualiza el total en pantalla', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: const Value(20)),
        );
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    final linea = lineaDesdeProducto(producto, cantidad: 2);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );

    await _pump(tester, db, ventaId: ventaId, usuarioId: usuarioId);

    // 112000*2 = 224000, redondea hacia arriba al paso de 10000 configurado → 230000.
    expect(find.text('\$2.300'), findsOneWidget);

    await tester.tap(find.byTooltip('Sumar uno'));
    await tester.pumpAndSettle();

    // 112000*3 = 336000 → 340000; la línea queda marcada con lo que cambió.
    expect(find.text('\$3.400'), findsOneWidget);
    expect(find.text('Antes \$2.300'), findsOneWidget);
    expect(find.text('Cambió: 2 → 3'), findsOneWidget);
  });

  testWidgets('guardar sin motivo no cierra la pantalla', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(900000), stock: const Value(5)),
        );
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    final venta = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );

    await _pump(tester, db, ventaId: ventaId, usuarioId: usuarioId);
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar')); // motivo vacío
    await tester.pumpAndSettle();

    expect(find.byType(PantallaEditorVenta), findsOneWidget);
  });
}
