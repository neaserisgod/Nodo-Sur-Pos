// Cubre la elección de canal para el resto de un mixto (fase 12): Enter y
// Alt+Q confirman con QR (mismo default de siempre), Alt+D confirma con
// Débito. Estas dos teclas son locales a este diálogo — el test que prueba
// que NO se filtran al handler global vive aparte, en
// handler_teclado_global_vs_dialogo_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/dialogo_mixto.dart';

Future<({int monto, String canal})?> _abrirYConfirmar(
  WidgetTester tester, {
  required String montoEscrito,
  required Future<void> Function(WidgetTester) confirmar,
}) async {
  ({int monto, String canal})? resultado;
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await mostrarDialogoMixto(
              context,
              totalCentavos: 1000000,
            );
          },
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), montoEscrito);
  await tester.pump();
  await confirmar(tester);
  await tester.pumpAndSettle();

  return resultado;
}

Future<void> _presionarAlt(
  WidgetTester tester,
  LogicalKeyboardKey tecla,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(tecla);
  await tester.sendKeyUpEvent(tecla);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
}

void main() {
  testWidgets('Enter confirma con el resto por QR (default)', (tester) async {
    final resultado = await _abrirYConfirmar(
      tester,
      montoEscrito: '3.000',
      confirmar: (tester) async =>
          tester.testTextInput.receiveAction(TextInputAction.done),
    );
    expect(resultado, (monto: 300000, canal: 'qr'));
  });

  testWidgets('Alt+Q confirma con el resto por QR', (tester) async {
    final resultado = await _abrirYConfirmar(
      tester,
      montoEscrito: '4.000',
      confirmar: (tester) async =>
          _presionarAlt(tester, LogicalKeyboardKey.keyQ),
    );
    expect(resultado, (monto: 400000, canal: 'qr'));
  });

  testWidgets('Alt+D confirma con el resto por Débito', (tester) async {
    final resultado = await _abrirYConfirmar(
      tester,
      montoEscrito: '4.000',
      confirmar: (tester) async =>
          _presionarAlt(tester, LogicalKeyboardKey.keyD),
    );
    expect(resultado, (monto: 400000, canal: 'debit_card'));
  });

  testWidgets('el botón Cobrar mixto usa QR, igual que Enter', (tester) async {
    final resultado = await _abrirYConfirmar(
      tester,
      montoEscrito: '1.000',
      confirmar: (tester) async => tester.tap(find.text('Cobrar mixto')),
    );
    expect(resultado, (monto: 100000, canal: 'qr'));
  });

  testWidgets('Alt+Q con un monto inválido no cierra el diálogo', (
    tester,
  ) async {
    ({int monto, String canal})? resultado;
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.oscuro,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await mostrarDialogoMixto(
                context,
                totalCentavos: 1000000,
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '999.999');
    await tester.pump();
    await _presionarAlt(tester, LogicalKeyboardKey.keyQ);
    await tester.pump();

    expect(resultado, isNull);
    expect(find.text('Pago mixto'), findsOneWidget);
  });
}
