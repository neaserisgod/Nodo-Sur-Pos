// El estado del bot al pie del menú lateral de la compu (`estado_bot_lateral_ns.dart`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantallas/estado_bot_lateral_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/servicios/bot_en_celular.dart';
import 'package:path/path.dart' as p;

import '../helpers/sitio_bot_falso.dart';

class _Motor extends MotorBot {
  _Motor(this.prendido);
  bool prendido;
  @override
  Future<bool> encendido() async => prendido;
  @override
  Future<void> encender({required String codigo, required String datos, required String numero}) async => prendido = true;
  @override
  Future<void> apagar() async => prendido = false;
  @override
  Future<String?> faltante() async => null;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bot_lateral'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> abrir(WidgetTester tester, {required bool encendido, Map<String, Object?>? estado}) async {
    if (estado != null) {
      final datos = Directory(p.join(tmp.path, 'bot-datos'))..createSync(recursive: true);
      File(p.join(datos.path, 'estado.json')).writeAsStringSync(jsonEncode(estado));
    }
    final bot = BotEnCelular(acceso: SitioBotFalso(), soporte: () async => tmp, motor: _Motor(encendido));
    await tester.pumpWidget(MaterialApp(
      theme: TemaCompanion.claro,
      home: Scaffold(body: MenuLateralNs(activa: PestaniaNs.inicio, onSeleccionar: (_) {}, abajo: EstadoBotLateralNs(bot: bot))),
    ));
    // Lee archivos de verdad: hay que dejar correr el reloj real entre cuadro y cuadro.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  testWidgets('apagado', (tester) async {
    await abrir(tester, encendido: false);
    expect(find.text('Apagado'), findsOneWidget);
  });

  testWidgets('conectado, con el último mensaje', (tester) async {
    await abrir(tester, encendido: true, estado: {
      'conectado': true,
      'ultimoMensaje': DateTime.now().subtract(const Duration(minutes: 4)).millisecondsSinceEpoch,
    });
    final texto = tester.widget<Text>(find.byKey(const Key('bot_lateral_estado'))).data!;
    expect(texto, startsWith('Conectado · último mensaje'));
  });

  testWidgets('falta vincular', (tester) async {
    await abrir(tester, encendido: true, estado: {'codigo': 'K7QM2XRA'});
    expect(find.text('Falta vincularlo con WhatsApp'), findsOneWidget);
  });
}
