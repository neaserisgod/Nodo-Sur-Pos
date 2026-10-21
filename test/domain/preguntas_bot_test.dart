import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/preguntas_bot.dart';

void main() {
  group('preguntasDeConfig / configConPreguntas', () {
    test('lee preguntas, pagos, envíos y emoji, e ignora lo que no tiene forma', () {
      final p = preguntasDeConfig({
        'preguntas': [
          {'titulo': 'Carne', 'claves': ['que carne', ' ', 3], 'respuesta': 'Aguja'},
          {'claves': 'no es lista', 'respuesta': 'x'},
          'cualquiera',
        ],
        'respuestas': {'pagos': 'Efectivo', 'envios': null},
        'textos': {'emoji': '🍔', 'quien_atiende': 'el local'},
      });
      expect(p.preguntas, hasLength(1));
      expect(p.preguntas.single.claves, ['que carne']);
      expect(p.preguntas.single.nombre, 'Carne');
      expect(p.pagos, 'Efectivo');
      expect(p.envios, '');
      expect(p.emoji, '🍔');
    });

    test('sin configuración: todo vacío', () {
      final p = preguntasDeConfig(null);
      expect(p.preguntas, isEmpty);
      expect(p.pagos, '');
    });

    test('guarda encima sin tocar lo demás; vacío va como null y el emoji vacío se saca', () {
      final anterior = {
        'numero_actual': '549',
        'textos': {'emoji': '🍗', 'quien_atiende': 'el local'},
        'respuestas': {'otra': 'queda'},
        'pedidos': {'cocina': 'normal'},
      };
      final c = configConPreguntas(
        anterior,
        const PreguntasDelBot(preguntas: [PreguntaBot(claves: ['que carne'], respuesta: 'Aguja')], pagos: ' Efectivo '),
      );
      expect(c['numero_actual'], '549');
      expect(c['pedidos'], {'cocina': 'normal'});
      expect(c['preguntas'], [
        {'claves': ['que carne'], 'respuesta': 'Aguja'}
      ]);
      expect(c['respuestas'], {'otra': 'queda', 'pagos': 'Efectivo', 'envios': null});
      expect(c['textos'], {'quien_atiende': 'el local'});
      expect(preguntasDeConfig(c).preguntas.single.respuesta, 'Aguja');
    });
  });

  group('leerBloquePreguntas', () {
    test('lee el encabezado y varias preguntas, con respuestas de varios renglones', () {
      final b = leerBloquePreguntas('''
emoji: 🍔
pagos: Efectivo o transferencia.
---
pregunta: ¿De qué es la carne?
claves: que carne, de que es la carne ,  son caseras
respuesta: Aguja picada.
Cada medallón es de 100 g.
---
pregunta: Promos
claves: promo, promos
respuesta:
• 2 simples — \$24.900
• 2 dobles — \$29.900
''');
      expect(b.errores, isEmpty);
      expect(b.emoji, '🍔');
      expect(b.pagos, 'Efectivo o transferencia.');
      expect(b.envios, isNull);
      expect(b.preguntas, hasLength(2));
      expect(b.preguntas[0].claves, ['que carne', 'de que es la carne', 'son caseras']);
      expect(b.preguntas[0].respuesta, 'Aguja picada.\nCada medallón es de 100 g.');
      expect(b.preguntas[1].respuesta, '• 2 simples — \$24.900\n• 2 dobles — \$29.900');
    });

    test('una pregunta sin claves o sin respuesta queda afuera con su error', () {
      final b = leerBloquePreguntas('pregunta: Sin claves\nrespuesta: algo\n---\nclaves: hola\n---\nclaves: ok\nrespuesta: bien');
      expect(b.preguntas, hasLength(1));
      expect(b.errores, hasLength(2));
      expect(b.errores.first, contains('Sin claves'));
    });

    test('"pagos:" adentro de una respuesta es parte de la respuesta', () {
      final b = leerBloquePreguntas('claves: como pago\nrespuesta: Te cuento.\npagos: efectivo');
      expect(b.pagos, isNull);
      expect(b.preguntas.single.respuesta, 'Te cuento.\npagos: efectivo');
    });
  });

  test('sumarBloque reemplaza por título, agrega lo nuevo y deja pagos si el bloque no lo trae', () {
    const actual = PreguntasDelBot(
      preguntas: [PreguntaBot(titulo: 'Carne', claves: ['que carne'], respuesta: 'vieja'), PreguntaBot(claves: ['veggie'], respuesta: 'no')],
      pagos: 'Efectivo',
    );
    final b = leerBloquePreguntas('pregunta: carne\nclaves: que carne\nrespuesta: nueva\n---\npregunta: Papas\nclaves: que papas\nrespuesta: bastón');
    final r = sumarBloque(actual, b);
    expect([for (final p in r.preguntas) p.respuesta], ['nueva', 'no', 'bastón']);
    expect(r.pagos, 'Efectivo');
  });

  test('avisosDeClave marca palabras sueltas cortas o que están en la carta, no frases', () {
    final a = avisosDeClave(['agua', 'cerveza', 'tienen cerveza', 'vegetariana'], nombresCarta: ['Cambio a cerveza artesanal']);
    expect(a, hasLength(2));
    expect(a[0], contains('agua'));
    expect(a[1], contains('está en la carta'));
  });

  test('problemasDePregunta', () {
    expect(problemasDePregunta(const PreguntaBot(claves: ['a'], respuesta: 'b')), isEmpty);
    expect(problemasDePregunta(const PreguntaBot(claves: [], respuesta: ' ')), hasLength(2));
  });
}
