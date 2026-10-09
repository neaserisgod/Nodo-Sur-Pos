import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_proveedores.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_facturas_compra.dart';
import 'package:la_plazoleta/domain/aplicar_factura.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Proveedores en el celular: la cuenta corriente (El dueño, 2026-10-07) y el alta y la edición (2026-10-09), sobre la base del celular.
void main() {
  late AppDatabase db;
  late int usuario;
  late int serra;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Dueño'});
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    serra = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
  });
  tearDown(() => db.close());

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: PantallaProveedores(db: db, usuarioId: usuario)));
    await esperar(tester);
  }

  testWidgets('muestra el total que debés y abre el libro de un proveedor', (tester) async {
    await cargarDeuda(db, proveedorId: serra, montoCentavos: 5000000, fecha: DateTime(2026, 10, 1), nota: 'Remito 12', usuarioId: usuario);
    await abrir(tester);
    expect(find.text('Les debés en total'), findsOneWidget);
    expect(find.text('Serra'), findsOneWidget);

    await tester.tap(find.text('Serra'));
    await esperar(tester);
    expect(find.text('Le debés'), findsOneWidget);
    expect(find.text('Remito 12'), findsOneWidget);
  });

  testWidgets('carga una deuda desde el celular y la anula', (tester) async {
    await abrir(tester);
    // Sin deuda no aparece en "Con deuda"; se lo busca por nombre.
    await tester.enterText(find.byType(TextField).first, 'serra');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serra'));
    await esperar(tester);

    await tester.tap(find.text('Cargar deuda').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12000');
    await tester.tap(find.text('Cargar deuda').last);
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(await saldoDeuda(db, serra), 1200000);
    final cargo = (await listarMovimientosDeuda(db, serra)).single;
    expect(cargo.globalId, isNotNull, reason: 'viaja a la PC');

    await tester.tap(find.text('Deuda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anular'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(await saldoDeuda(db, serra), 0);
    expect(find.textContaining('anulado'), findsOneWidget);
  });

  testWidgets('un cargo de factura se deshace entero (deuda y stock), no se anula solo', (tester) async {
    final crema = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Crema', proveedorId: Value(serra), precioCentavos: const Value(300000), costoCentavos: const Value(200000), stock: const Value(3)),
        );
    await aplicarFactura(
      db,
      proveedorId: serra,
      numero: '0001-1',
      tipo: 'A',
      totalImpresoCentavos: 800000,
      lineas: [LineaParaAplicar(productoId: crema, unidades: 4, totalCentavos: 800000)],
      sumarStock: true,
      usuarioId: usuario,
    );
    await abrir(tester);
    await tester.tap(find.text('Serra'));
    await esperar(tester);
    expect(find.textContaining('factura cargada'), findsOneWidget);

    await tester.tap(find.text('Factura 0001-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer factura'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 8));

    expect(await saldoDeuda(db, serra), 0);
    final p = await (db.select(db.productos)..where((t) => t.id.equals(crema))).getSingle();
    expect(p.stock, 3, reason: 'se resta lo que sumó la factura');
  });

  testWidgets('"Pagar" abre el pago con el proveedor ya elegido y la deuda sugerida', (tester) async {
    await cargarDeuda(db, proveedorId: serra, montoCentavos: 5000000, fecha: DateTime(2026, 10, 1), usuarioId: usuario);
    await abrir(tester);
    await tester.tap(find.text('Serra'));
    await esperar(tester);
    await tester.tap(find.text('Pagar'));
    await esperar(tester);
    expect(find.text('Pagar proveedor'), findsOneWidget);
    expect(find.textContaining('Saldo con este proveedor'), findsOneWidget);
    expect(find.text('Se paga toda la deuda.'), findsOneWidget);
  });

  Finder campo(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));

  testWidgets('da de alta un proveedor con sus días y su medio de pago, y abre su ficha', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('+ Nuevo'));
    await esperar(tester);
    expect(find.text('Nuevo proveedor'), findsOneWidget);

    await tester.enterText(campo('Nombre'), 'Lácteos del Sur');
    await tester.enterText(campo('WhatsApp (opcional)'), '294 412-3456');
    await tester.tap(find.text('Mar').first); // le pedís el martes
    await tester.tap(find.text('Jue').last); // te entrega el jueves
    await tester.tap(find.text('Transferencia'));
    await tester.pump();
    await tester.tap(find.text('Dar de alta'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));

    final nuevo = await (db.select(db.proveedores)..where((p) => p.nombre.equals('Lácteos del Sur'))).getSingle();
    expect(nuevo.codigo, 'LDS');
    expect(nuevo.diaPedido, 'Martes');
    expect(nuevo.diaEntrega, 'Jueves');
    expect(nuevo.medioPago, 'Transferencia');
    expect(nuevo.whatsapp, '294 412-3456');
    expect(nuevo.globalId, isNotNull, reason: 'viaja a la PC');
    // Queda en su ficha, con los datos a la vista.
    expect(find.text('Lácteos del Sur'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
  });

  testWidgets('no deja dar de alta dos proveedores con el mismo nombre', (tester) async {
    await abrir(tester);
    await tester.tap(find.text('+ Nuevo'));
    await esperar(tester);
    final antes = (await db.select(db.proveedores).get()).length;
    await tester.enterText(campo('Nombre'), 'serra');
    await tester.tap(find.text('Dar de alta'));
    await esperar(tester);
    expect(find.text('Ya hay un proveedor llamado "serra"'), findsOneWidget);
    expect(await db.select(db.proveedores).get(), hasLength(antes));
  });

  testWidgets('editar: cambia los datos sin tocar el código, y darlo de baja lo manda al final', (tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField).first, 'serra');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serra'));
    await esperar(tester);
    await tester.tap(find.text('Editar'));
    await esperar(tester);
    expect(find.text('Editar proveedor'), findsOneWidget);

    await tester.enterText(campo('Nombre'), 'Serra Hnos');
    await tester.tap(find.text('Activo'));
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await esperar(tester);
    await tester.pump(const Duration(seconds: 6));

    final p = await (db.select(db.proveedores)..where((t) => t.id.equals(serra))).getSingle();
    expect(p.nombre, 'Serra Hnos');
    expect(p.codigo, 'SE');
    expect(p.activo, isFalse);
    expect(find.textContaining('Dado de baja'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await esperar(tester);
    expect(find.text('Dados de baja'.toUpperCase()), findsOneWidget);
  });

  testWidgets('"Pedir por WhatsApp" abre el chat con lo que está bajo el mínimo', (tester) async {
    await (db.update(db.proveedores)..where((t) => t.id.equals(serra))).write(const ProveedoresCompanion(whatsapp: Value('2944123456')));
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Queso cremoso', proveedorId: Value(serra), stock: const Value(1), stockMinimo: const Value(4)));
    Uri? abierta;
    abrirUrlParaTestsNs = (u) async {
      abierta = u;
      return true;
    };
    addTearDown(() => abrirUrlParaTestsNs = null);

    await abrir(tester);
    await tester.enterText(find.byType(TextField).first, 'serra');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serra'));
    await esperar(tester);
    await tester.tap(find.text('Pedir por WhatsApp'));
    await esperar(tester);

    expect(abierta?.host, 'wa.me');
    expect(abierta?.path, '/5492944123456');
    expect(abierta?.queryParameters['text'], contains('Queso cremoso'));
  });
}
