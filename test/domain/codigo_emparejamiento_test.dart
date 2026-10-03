import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/codigo_emparejamiento.dart';

void main() {
  late DateTime ahora;
  late GestorCodigoEmparejamiento g;
  setUp(() {
    ahora = DateTime(2026, 10, 3, 12);
    g = GestorCodigoEmparejamiento(reloj: () => ahora, azar: Random(1));
  });

  test('seis números, sirve una sola vez', () {
    final c = g.generar();
    expect(c, matches(RegExp(r'^\d{6}$')));
    expect(g.canjear(c), ResultadoCanje.ok);
    expect(g.canjear(c), ResultadoCanje.sinCodigo);
    expect(g.codigo, isNull);
  });

  test('vence a los 5 minutos', () {
    final c = g.generar();
    ahora = ahora.add(const Duration(minutes: 4, seconds: 59));
    expect(g.restante, const Duration(seconds: 1));
    ahora = ahora.add(const Duration(seconds: 1));
    expect(g.codigo, isNull);
    expect(g.canjear(c), ResultadoCanje.vencido);
  });

  test('a los 5 intentos fallidos se anula, aunque después se acierte', () {
    final c = g.generar();
    final malo = c == '000000' ? '111111' : '000000';
    for (var i = 0; i < 4; i++) {
      expect(g.canjear(malo), ResultadoCanje.incorrecto);
    }
    expect(g.canjear(malo), ResultadoCanje.anulado);
    expect(g.canjear(c), ResultadoCanje.sinCodigo);
  });

  test('generar otro anula el anterior y reinicia los intentos', () {
    final viejo = g.generar();
    final nuevo = g.generar();
    if (viejo != nuevo) expect(g.canjear(viejo), ResultadoCanje.incorrecto);
    expect(g.canjear(nuevo), ResultadoCanje.ok);
  });
}
