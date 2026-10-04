// Etapa C: el botón "Tarjeta" pregunta Débito o Crédito (1 pago), con las teclas D y C.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/cobro_posnet.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/elegir_tarjeta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  Future<VentaControlador> abrir(WidgetTester tester) async {
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final c = VentaControlador(db);
    await c.cargarTodo();
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Scaffold(
        body: Builder(builder: (context) => ElevatedButton(onPressed: () => elegirTarjeta(context, c), child: const Text('Tarjeta'))),
      ),
    ));
    await tester.tap(find.text('Tarjeta'));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('la tecla C elige crédito; la D, débito', (tester) async {
    final c = await abrir(tester);
    expect(find.text('Cobrar con tarjeta'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(c.canalElegido, canalCredito);
    expect(find.text('Cobrar con tarjeta'), findsNothing);

    await tester.tap(find.text('Tarjeta'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pumpAndSettle();
    expect(c.canalElegido, canalDebito);
    c.dispose();
  });

  testWidgets('con el mouse: "Crédito, 1 pago"; cancelar no cambia nada', (tester) async {
    final c = await abrir(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(c.canalElegido, isNull);
    await tester.tap(find.text('Tarjeta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tarjeta_credito')));
    await tester.pumpAndSettle();
    expect(c.canalElegido, canalCredito);
    c.dispose();
  });
}
