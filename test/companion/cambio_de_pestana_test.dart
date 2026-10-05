// El cambio de pestaña repite la entrada (fundido cruzado) sin perder lo que tenían las pestañas, y respeta "reducir movimiento".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';

Widget _app(int indice, {bool sinMov = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: sinMov),
        child: CambioDePestanaNs(
          indice: indice,
          child: IndexedStack(index: indice, children: const [Text('uno'), Text('dos')]),
        ),
      ),
    );

double _opacidad(WidgetTester t) {
  final f = t.widget<FadeTransition>(find.descendant(of: find.byType(CambioDePestanaNs), matching: find.byType(FadeTransition)).first);
  return f.opacity.value;
}

void main() {
  testWidgets('al cambiar de pestaña la nueva entra con fundido, no de golpe', (t) async {
    await t.pumpWidget(_app(0));
    expect(_opacidad(t), 1, reason: 'la primera vez no se anima');
    await t.pumpWidget(_app(1));
    await t.pump(const Duration(milliseconds: 30));
    expect(_opacidad(t), lessThan(1), reason: 'recién empieza a aparecer');
    await t.pumpAndSettle();
    expect(_opacidad(t), 1);
    expect(find.text('dos'), findsOneWidget);
  });

  testWidgets('con reducir movimiento cambia al instante', (t) async {
    await t.pumpWidget(_app(0, sinMov: true));
    await t.pumpWidget(_app(1, sinMov: true));
    await t.pump(const Duration(milliseconds: 30));
    expect(_opacidad(t), 1);
  });
}
