// Pedido por WhatsApp (rediseño v4, etapa 8.2): el número del proveedor y el mensaje con lo que hay que pedir.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/pedido_whatsapp.dart';

void main() {
  group('normalizarWhatsapp', () {
    test('un celular argentino con o sin signos queda como 549 + característica + número', () {
      expect(normalizarWhatsapp('+54 9 294 412-3456'), '5492944123456');
      expect(normalizarWhatsapp('294 4123456'), '5492944123456');
      expect(normalizarWhatsapp('(294) 412-3456'), '5492944123456');
    });

    test('con el 0 de la característica y el 15 del celular, los saca', () {
      expect(normalizarWhatsapp('0294 15 4123456'), '5492944123456');
      expect(normalizarWhatsapp('(0294) 15-412-3456'), '5492944123456');
    });

    test('54 sin el 9 lo agrega', () {
      expect(normalizarWhatsapp('54 294 4123456'), '5492944123456');
    });

    test('un número internacional (otro país) se deja como está', () {
      expect(normalizarWhatsapp('+598 99 123 456'), '59899123456');
    });

    test('vacío o muy corto no es un número', () {
      expect(normalizarWhatsapp(''), isNull);
      expect(normalizarWhatsapp('   '), isNull);
      expect(normalizarWhatsapp('1234'), isNull);
      expect(normalizarWhatsapp('abc'), isNull);
    });
  });

  group('urlWhatsapp', () {
    test('arma el link de wa.me con el texto codificado', () {
      final u = urlWhatsapp('5492944123456', 'Hola, necesito:\n- Alfajor');
      expect(u.scheme, 'https');
      expect(u.host, 'wa.me');
      expect(u.path, '/5492944123456');
      expect(u.queryParameters['text'], 'Hola, necesito:\n- Alfajor');
    });
  });

  group('armarMensajePedido', () {
    test('lista cada producto con lo que queda', () {
      final m = armarMensajePedido(
        proveedor: 'Serra',
        comercio: 'La Plazoleta',
        lineas: [
          const LineaDePedido(nombre: 'Alfajor triple', stock: 2),
          const LineaDePedido(nombre: 'Queso barra', stock: 1500, esPesable: true),
          const LineaDePedido(nombre: 'Yerba 1 kg', stock: 0),
        ],
      );
      expect(m, startsWith('Hola Serra, te escribe La Plazoleta. Necesito pedir:'));
      expect(m, contains('- Alfajor triple (quedan 2)'));
      expect(m, contains('- Queso barra (quedan 1,5 kg)'));
      expect(m, contains('- Yerba 1 kg (no queda)'));
      expect(m, endsWith('Gracias.'));
    });

    test('el stock negativo también es "no queda"; sin comercio no lo nombra', () {
      final m = armarMensajePedido(proveedor: 'Serra', lineas: [const LineaDePedido(nombre: 'Coca', stock: -3)]);
      expect(m, startsWith('Hola Serra. Necesito pedir:'));
      expect(m, contains('- Coca (no queda)'));
    });

    test('gramos que no son kilos redondos usan coma decimal', () {
      final m = armarMensajePedido(proveedor: 'X', lineas: [const LineaDePedido(nombre: 'Jamón', stock: 250, esPesable: true)]);
      expect(m, contains('- Jamón (quedan 0,25 kg)'));
    });
  });
}
