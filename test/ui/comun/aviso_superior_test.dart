// Aviso de arriba (rediseño v4): sale arriba, no tapa el cobro, reemplaza al anterior, la acción corre y se va solo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/comun/aviso_superior.dart';

Widget _app(void Function(BuildContext) alTocar) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(onPressed: () => alTocar(context), child: const Text('mostrar')),
      ),
    ),
  ),
);

void main() {
  testWidgets('aparece arriba, centrado, y se va solo', (tester) async {
    await tester.pumpWidget(_app((c) => mostrarAviso(c, 'Guardado')));
    await tester.tap(find.text('mostrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardado'), findsOneWidget);
    final caja = tester.getRect(find.byKey(const Key('aviso_superior')));
    // Arriba del todo (no abajo como el SnackBar) y centrado.
    expect(caja.top, lessThan(80));
    expect(caja.center.dx, closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2, 1));
    // La permanencia se cuenta desde que terminó de entrar (la entrada dura 450 ms): con eso vencido, empieza a irse.
    await tester.pump(duracionAvisoSimple + const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsNothing);
  });

  testWidgets('uno nuevo reemplaza al anterior', (tester) async {
    var n = 0;
    await tester.pumpWidget(_app((c) => mostrarAviso(c, 'Aviso ${++n}')));
    await tester.tap(find.text('mostrar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('mostrar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aviso 1'), findsNothing);
    expect(find.text('Aviso 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // desmontar cancela el temporizador: nada queda pendiente
  });

  testWidgets('con acción: tocarla la corre y saca el aviso', (tester) async {
    var deshecho = 0;
    await tester.pumpWidget(
      _app((c) => mostrarAviso(c, 'Quitaste Coca', textoAccion: 'Deshacer', alAccionar: () => deshecho++)),
    );
    await tester.tap(find.text('mostrar'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deshacer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('aviso_superior_accion')));
    await tester.pump();
    expect(deshecho, 1);
    expect(find.text('Quitaste Coca'), findsNothing);
  });

  testWidgets('con acción dura más que uno simple', (tester) async {
    await tester.pumpWidget(_app((c) => mostrarAviso(c, 'Con deshacer', textoAccion: 'Deshacer', alAccionar: () {})));
    await tester.tap(find.text('mostrar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(duracionAvisoSimple);
    expect(find.text('Con deshacer'), findsOneWidget);
    await tester.pump(duracionAvisoConAccion); // el tiempo pasa de largo: empieza a irse
    await tester.pumpAndSettle();
    expect(find.text('Con deshacer'), findsNothing);
  });
}
