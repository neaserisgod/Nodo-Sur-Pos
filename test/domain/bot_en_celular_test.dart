import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/bot_en_celular.dart';

void main() {
  final ahora = DateTime(2026, 10, 10, 21);
  final ms = ahora.millisecondsSinceEpoch;

  group('estado.json del bot', () {
    test('lo que escribe el bot', () {
      final e = EstadoBotLocal.desdeJson({'conectado': true, 'codigo': null, 'desde': ms, 'ultimoMensaje': ms - 300000, 'pid': 12});
      expect(e.conectado, isTrue);
      expect(e.codigo, isNull);
      expect(e.ultimoMensaje, ahora.subtract(const Duration(minutes: 5)));
    });

    test('un archivo roto o de otra versión no rompe: queda vacío', () {
      for (final j in [null, 'texto', 3, [], {'conectado': 'sí', 'codigo': '  ', 'desde': 'ayer'}]) {
        final e = EstadoBotLocal.desdeJson(j);
        expect(e.conectado, isFalse);
        expect(e.codigo, isNull);
        expect(e.desde, isNull);
      }
    });
  });

  group('fase', () {
    test('apagado gana sobre lo que haya quedado escrito', () {
      expect(faseDelBot(encendido: false, estado: const EstadoBotLocal(conectado: true)), FaseBot.apagado);
    });
    test('recién encendido, sin estado todavía: conectando', () {
      expect(faseDelBot(encendido: true), FaseBot.conectando);
    });
    test('con código: falta vincular; conectado: atiende; desvinculado gana', () {
      expect(faseDelBot(encendido: true, estado: const EstadoBotLocal(codigo: 'ABCD1234')), FaseBot.vincular);
      expect(faseDelBot(encendido: true, estado: const EstadoBotLocal(conectado: true)), FaseBot.conectado);
      expect(faseDelBot(encendido: true, estado: const EstadoBotLocal(deslogueado: true, codigo: 'X')), FaseBot.desvinculado);
    });
  });

  test('textos', () {
    expect(textoDelBot(FaseBot.conectado, EstadoBotLocal(conectado: true, ultimoMensaje: ahora.subtract(const Duration(minutes: 5))), ahora),
        'Conectado · último mensaje hace 5 min');
    expect(textoDelBot(FaseBot.conectado, const EstadoBotLocal(conectado: true), ahora), 'Conectado y atendiendo');
    expect(textoDelBot(FaseBot.conectado, EstadoBotLocal(ultimoMensaje: ahora.subtract(const Duration(days: 1))), ahora), contains('hace 1 día'));
    expect(textoDelBot(FaseBot.vincular, null, ahora), 'Falta vincularlo con WhatsApp');
  });

  test('código como lo muestra WhatsApp', () {
    expect(codigoLegible('abcd1234'), 'ABCD-1234');
    expect(codigoLegible('ABCD-1234'), 'ABCD-1234');
    expect(codigoLegible('XYZ'), 'XYZ');
  });

  test('el token del bot se pide de nuevo si no hay o vence en menos de 30 días', () {
    expect(tokenBotPorVencer(venceSegundos: null, ahora: ahora), isTrue);
    expect(tokenBotPorVencer(venceSegundos: ms ~/ 1000 + 29 * 86400, ahora: ahora), isTrue);
    expect(tokenBotPorVencer(venceSegundos: ms ~/ 1000 + 31 * 86400, ahora: ahora), isFalse);
  });
}
