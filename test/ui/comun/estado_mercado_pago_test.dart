import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/ui/comun/estado_mercado_pago.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

void main() {
  test('cada estado dice qué falta y quién lo arregla', () {
    expect(vistaDeEstadoMp(null).titulo, 'No se pudo leer');
    expect(vistaDeEstadoMp(const EstadoMp(conectado: false, necesitaReconectar: false, terminalElegida: false)).titulo, 'Sin conectar');
    expect(vistaDeEstadoMp(const EstadoMp(conectado: false, necesitaReconectar: true, terminalElegida: true)).titulo, 'Hay que reconectarlo');
    expect(vistaDeEstadoMp(const EstadoMp(conectado: true, necesitaReconectar: false, terminalElegida: false)).listo, isFalse);
    expect(vistaDeEstadoMp(const EstadoMp(conectado: true, necesitaReconectar: false, terminalElegida: true)).listo, isTrue);
  });

  testWidgets('muestra el estado leído y el botón abre el sitio', (tester) async {
    var abierto = false;
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Scaffold(
        body: EstadoMercadoPago(
          leer: () async => const EstadoMp(conectado: true, necesitaReconectar: false, terminalElegida: true),
          abrir: () async => abierto = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mercado Pago: Conectado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mp_abrir_negocio')));
    expect(abierto, isTrue);
  });

  testWidgets('sin red avisa y deja reintentar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Scaffold(body: EstadoMercadoPago(leer: () async => throw const ErrorNube('sin_red', 'sin red'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mercado Pago: No se pudo leer'), findsOneWidget);
    expect(find.byKey(const Key('mp_reintentar')), findsOneWidget);
  });
}
