// "Mercado Pago según Mercado Pago" en el cierre: muestra comisiones, la diferencia de cobros y lo que sobra de cada lado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/conciliacion_mp.dart';
import 'package:la_plazoleta/ui/cierre/seccion_mp_real.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

Widget _app(Widget w) => MaterialApp(theme: TemaPlazoleta.claro, home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('con un cobro sin venta: diferencia en rojo y el cobro listado', (tester) async {
    final c = conciliarMp(
      cobros: [
        CobroMp(id: '1', estado: 'approved', fecha: DateTime(2026, 10, 1, 11), montoCentavos: 360000, devueltoCentavos: 0, comisionCentavos: 7200, netoCentavos: 352800, medio: 'account_money'),
        CobroMp(id: '2', estado: 'approved', fecha: DateTime(2026, 10, 1, 12, 5), montoCentavos: 500000, devueltoCentavos: 0, comisionCentavos: 10000, netoCentavos: 490000, medio: 'debit_card'),
      ],
      registrados: [PagoMpRegistrado(ventaId: 7, fecha: DateTime(2026, 10, 1, 11), montoCentavos: 360000)],
    );
    await tester.pumpWidget(_app(SeccionMpReal(cargar: () async => c, mpEsperadoCentavos: 1360000, mpContadoCentavos: 1832800)));
    await tester.pumpAndSettle();
    expect(find.text('Cobros en Mercado Pago sin venta en el sistema'), findsOneWidget);
    expect(find.textContaining('12:05'), findsOneWidget);
    expect(find.byKey(const Key('mp_real_diferencia_cobros')), findsOneWidget);
    expect(find.byKey(const Key('mp_real_diferencia')), findsOneWidget);
  });

  testWidgets('sin cuenta vinculada no consulta nada y lo explica', (tester) async {
    await tester.pumpWidget(_app(const SeccionMpReal(cargar: null, mpEsperadoCentavos: 0)));
    expect(find.textContaining('Vinculá este equipo'), findsOneWidget);
  });

  testWidgets('si falla la consulta lo dice y deja reintentar', (tester) async {
    var veces = 0;
    await tester.pumpWidget(_app(SeccionMpReal(cargar: () async {
      veces++;
      throw 'sin internet';
    }, mpEsperadoCentavos: 0)));
    await tester.pumpAndSettle();
    expect(find.textContaining('sin internet'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a consultar'));
    await tester.pumpAndSettle();
    expect(veces, 2);
  });
}
