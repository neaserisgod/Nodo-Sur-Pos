// "Pagar proveedor" rápido (rediseño v4): buscar, Enter elige, el monto viene con toda la deuda, Enter paga.
// Usa el mismo `pagarDeuda` que la cuenta corriente, así que el saldo y la caja quedan como siempre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/dialogo_pagar_proveedor_rapido.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int quilmes;
  late int arcor;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 1000000);
    quilmes = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'QU', nombre: 'Cervecería Quilmes'));
    arcor = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'AR', nombre: 'Arcor'));
    await cargarDeuda(db, proveedorId: quilmes, montoCentavos: 5400000, fecha: DateTime(2026, 10, 1), usuarioId: usuarioId);
    await cargarDeuda(db, proveedorId: arcor, montoCentavos: 3820000, fecha: DateTime(2026, 10, 1), usuarioId: usuarioId);
  });
  tearDown(() => db.close());

  PagoProveedorHecho? hecho;

  Future<void> abrir(WidgetTester tester, {int? sesion}) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    hecho = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.claro,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => hecho = await mostrarDialogoPagarProveedorRapido(context, db: db, usuarioId: usuarioId, sesionCajaId: sesion),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('lista con la deuda más grande arriba y filtra al escribir (sin importar acentos ni mayúsculas)', (tester) async {
    await abrir(tester, sesion: sesionId);
    final filas = tester.widgetList<InkWell>(find.byWidgetPredicate((w) => w is InkWell && w.key.toString().contains('pago_rapido_proveedor_')));
    expect(filas.first.key, Key('pago_rapido_proveedor_$quilmes'), reason: 'Quilmes debe más que Arcor');
    await tester.enterText(find.byKey(const Key('pago_rapido_busqueda')), 'ARC');
    await tester.pump();
    expect(find.byKey(Key('pago_rapido_proveedor_$arcor')), findsOneWidget);
    expect(find.byKey(Key('pago_rapido_proveedor_$quilmes')), findsNothing);
    await tester.enterText(find.byKey(const Key('pago_rapido_busqueda')), 'zzz');
    await tester.pump();
    expect(find.text('Sin coincidencias'), findsOneWidget);
  });

  testWidgets('escribir, Enter, Enter: elige el proveedor, el monto ya viene con toda la deuda y paga del cajón', (tester) async {
    await abrir(tester, sesion: sesionId);
    await tester.enterText(find.byKey(const Key('pago_rapido_busqueda')), 'quil');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter elige
    await tester.pumpAndSettle();
    expect(find.textContaining('Le debés'), findsWidgets);
    expect(tester.widget<TextField>(find.descendant(of: find.byKey(const Key('pago_rapido_monto')), matching: find.byType(TextField))).controller!.text, contains('54.000'));
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter paga
    await tester.pumpAndSettle();
    expect(hecho, isNotNull);
    expect(hecho!.proveedorNombre, 'Cervecería Quilmes');
    expect(hecho!.montoCentavos, 5400000);
    expect(hecho!.origen, OrigenPagoDeuda.cajon);
    expect(hecho!.deshacible, isTrue);
    expect(await saldoDeuda(db, quilmes), 0);
    expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).get(), hasLength(1));
  });

  testWidgets('pagar de más pide confirmar con un segundo toque y ese pago no se puede deshacer', (tester) async {
    await abrir(tester, sesion: sesionId);
    await tester.tap(find.byKey(Key('pago_rapido_proveedor_$arcor')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('pago_rapido_monto')), matching: find.byType(TextField)), '40000');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pago_rapido_error')), findsOneWidget);
    expect(hecho, isNull, reason: 'todavía no pagó');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(hecho, isNotNull);
    expect(hecho!.deshacible, isFalse);
  });

  testWidgets('sin caja abierta solo ofrece "Fuera de la caja"', (tester) async {
    await abrir(tester, sesion: null);
    await tester.tap(find.byKey(Key('pago_rapido_proveedor_$arcor')));
    await tester.pumpAndSettle();
    expect(find.text('Fuera de la caja'), findsOneWidget);
    expect(find.text('Del cajón'), findsNothing);
  });
}
