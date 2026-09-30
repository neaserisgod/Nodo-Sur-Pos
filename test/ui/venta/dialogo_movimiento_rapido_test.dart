import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/dialogo_movimiento_rapido.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _abrir(WidgetTester tester, AppDatabase db, int sesionId, int usuarioId) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => mostrarDialogoGastoRapido(context, db: db, sesionCajaId: sesionId, usuarioId: usuarioId),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  testWidgets('por defecto anota el gasto en la caja normal, sin medio de pago', (tester) async {
    await _abrir(tester, db, sesionId, usuarioId);

    await tester.enterText(find.byType(TextField).first, '5.000');
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();

    final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    final movimiento = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).getSingle();
    expect(movimiento.cajaId, cajaNormal.id);
    expect(movimiento.medioPagoId, isNull);
    expect(movimiento.montoCentavos, 500000);
  });

  testWidgets('elegir Mercado Pago queda en la caja normal pero marcado con medioPagoId de MP', (tester) async {
    await _abrir(tester, db, sesionId, usuarioId);

    await tester.enterText(find.byType(TextField).first, '3.000');
    await tester.tap(find.text('Mercado Pago'));
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();

    final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    final medioMp = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
    final movimiento = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).getSingle();
    expect(movimiento.cajaId, cajaNormal.id);
    expect(movimiento.medioPagoId, medioMp.id);
  });

  testWidgets('elegir Lata cigarrillos va a la caja de lata, sin medio de pago', (tester) async {
    await _abrir(tester, db, sesionId, usuarioId);

    await tester.enterText(find.byType(TextField).first, '2.000');
    await tester.tap(find.text('Lata cigarrillos'));
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();

    final cajaLata = await (db.select(db.cajas)..where((c) => c.esLata.equals(true))).getSingle();
    final movimiento = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesionId))).getSingle();
    expect(movimiento.cajaId, cajaLata.id);
    expect(movimiento.medioPagoId, isNull);
  });
}
