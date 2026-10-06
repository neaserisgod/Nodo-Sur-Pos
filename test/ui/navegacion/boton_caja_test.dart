// "Caja ▾" de la navbar (rediseño v4): muestra el estado de la caja y abre el menú con las acciones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/boton_caja.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

Widget _app(Widget hijo) => MaterialApp(theme: TemaPlazoleta.claro, home: Scaffold(body: Align(alignment: Alignment.topLeft, child: hijo)));

void main() {
  testWidgets('muestra el estado de la caja en el botón', (tester) async {
    for (final (estado, texto) in [
      (EstadoCajaNavbar.abierta, 'Caja abierta'),
      (EstadoCajaNavbar.cerrada, 'Caja cerrada'),
      (EstadoCajaNavbar.deAyerSinCerrar, 'Caja de ayer sin cerrar'),
    ]) {
      await tester.pumpWidget(_app(BotonCaja(estado: estado, acciones: const [])));
      expect(find.text(texto), findsOneWidget);
    }
  });

  testWidgets('abre el menú, cada fila corre su acción y el menú se cierra', (tester) async {
    final hechas = <String>[];
    await tester.pumpWidget(
      _app(
        BotonCaja(
          estado: EstadoCajaNavbar.abierta,
          detalle: 'desde las 8:02',
          acciones: [
            AccionMenuCaja(clave: 'arqueo', etiqueta: 'Hacer arqueo', icono: Icons.history, nota: 'pendiente', onTap: () => hechas.add('arqueo')),
            AccionMenuCaja(clave: 'gasto', etiqueta: 'Gasto', icono: Icons.add, atajo: '-', onTap: () => hechas.add('gasto')),
            AccionMenuCaja(clave: 'cerrar', etiqueta: 'Cerrar caja', icono: Icons.lock, peligro: true, separadorAntes: true, onTap: () => hechas.add('cerrar')),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('menu_caja_gasto')), findsNothing);
    await tester.tap(find.byKey(const Key('boton_caja')));
    await tester.pumpAndSettle();
    expect(find.text('Caja abierta · desde las 8:02'), findsOneWidget);
    expect(find.text('pendiente'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu_caja_gasto')));
    await tester.pumpAndSettle();
    expect(hechas, ['gasto']);
    expect(find.byKey(const Key('menu_caja_gasto')), findsNothing, reason: 'elegir una fila cierra el menú');
  });

  testWidgets('una fila sin acción está apagada y no hace nada', (tester) async {
    await tester.pumpWidget(
      _app(BotonCaja(estado: EstadoCajaNavbar.cerrada, acciones: const [AccionMenuCaja(clave: 'turno', etiqueta: 'Cambiar de turno', icono: Icons.swap_horiz, onTap: null)])),
    );
    await tester.tap(find.byKey(const Key('boton_caja')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_caja_turno')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_caja_turno')), findsOneWidget, reason: 'sigue abierto: no había nada que correr');
  });
}
