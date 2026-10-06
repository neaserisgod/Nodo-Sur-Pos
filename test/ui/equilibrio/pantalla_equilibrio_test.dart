import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/ui/equilibrio/pantalla_equilibrio.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` fuera del `TextField`
/// (fija, no la flotante de Material) — cada campo que un test necesita
/// tocar tiene una `Key` propia en el widget que lo instancia.
Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db, {required int usuarioId, int? sesionCajaId}) async {
  // Como la monta Inicio (mock v4, "Este mes"): alto acotado y ancho de la PC del local. Las tres tarjetas reparten el
  // alto y cada una scrollea sola, así que la pantalla no va adentro de otro scroll.
  tester.view.physicalSize = const Size(1920, 1040);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Scaffold(
        body: ContenidoEquilibrio(db: db, usuarioId: usuarioId, sesionCajaId: sesionCajaId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('avisar antes que inventar (pedido explícito de Dueño)', () {
    testWidgets('sin ningún fijo cargado, avisa en vez de mostrar números', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));

      final conceptos = await db.select(db.gastosFijos).get();
      await _pump(tester, db, usuarioId: usuarioId);

      expect(find.textContaining('Sin cargar este mes'), findsOneWidget);
      expect(find.textContaining('Falta cargar:'), findsOneWidget, reason: 'la cifra de avance dice qué falta en vez de un %');
      expect(find.text('—'), findsOneWidget, reason: 'sin fijos no hay venta diaria de equilibrio');
      expect(find.text('Falta cargar'), findsNWidgets(conceptos.length));
    });

    testWidgets('cargar el monto de un concepto lo saca del aviso', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));

      final conceptos = await db.select(db.gastosFijos).get();
      await _pump(tester, db, usuarioId: usuarioId);

      await tester.tap(find.text('Cargar').first);
      await tester.pumpAndSettle();
      await tester.enterText(_campo('campo_monto_fijo'), '935000');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Falta cargar'), findsNWidgets(conceptos.length - 1));
    });
  });

  group('margen ponderado real (no un porcentaje fijo)', () {
    testWidgets('el margen se calcula de lo realmente vendido', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: Value(DateTime.now()),
              subtotalCentavos: 1000,
              totalCentavos: 1000,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              precioUnitarioCentavos: 1000,
              costoUnitarioCentavos: const Value(650),
            ),
          );

      await _pump(tester, db, usuarioId: usuarioId);

      expect(find.textContaining('35 % de lo vendido'), findsOneWidget);
      expect(find.text('Ganancia bruta (35 %)'), findsOneWidget);
    });
  });

  group('fijos pendientes y reserva diaria — completos con todos los fijos cargados', () {
    testWidgets('con todos los fijos cargados, muestra el equilibrio, pendientes y reserva reales', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final mesAnio = mesAnioDe(DateTime.now());
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 25000000);
      }

      await _pump(tester, db, usuarioId: usuarioId);

      expect(find.text('Falta para cubrir los fijos'), findsOneWidget); // sin ganancia todavía, no cubierto
      expect(find.text('0 %'), findsOneWidget);
      expect(find.textContaining('Presupuestado'), findsOneWidget);
      expect(find.textContaining('Pendiente \$'), findsOneWidget);
      expect(find.text('Falta cargar'), findsNothing);
    });

    testWidgets('registrar un pago de un fijo reduce lo pendiente', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final mesAnio = mesAnioDe(DateTime.now());
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 25000000);
      }

      await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);

      await tester.tap(find.text('Pagar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      expect(find.text('Pagado'), findsOneWidget, reason: 'ese concepto quedó pagado');
      expect(find.textContaining(r'Pagado $ 250.000'), findsOneWidget);
    });

    testWidgets('el diálogo de pago permite elegir una fecha distinta de hoy', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final mesAnio = mesAnioDe(DateTime.now());
      final conceptos = await db.select(db.gastosFijos).get();
      for (final c in conceptos) {
        await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 25000000);
      }
      final alquilerId = conceptos.firstWhere((c) => c.nombre == 'Alquiler').id;

      await _pump(tester, db, usuarioId: usuarioId, sesionCajaId: sesionId);

      await tester.tap(find.text('Pagar').first);
      await tester.pumpAndSettle();
      // El dueño pagó el 31/07 pero lo carga recién ahora: la fecha del pago,
      // no la de carga, es la que tiene que quedar en el movimiento.
      await tester.enterText(_campo('campo_fecha_pago_fijo'), '31/07/2026');
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      final movimiento = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.gastoFijoId.equals(alquilerId)))
          .getSingle();
      expect(movimiento.fecha, DateTime(2026, 7, 31));
    });
  });

}
