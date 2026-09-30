import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/vinculacion.dart';

void main() {
  group('PKCE', () {
    test('el verificador y el state tienen el largo y los caracteres que acepta el sitio', () {
      final v = generarVerificador();
      expect(v.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v), isTrue);
      final s = generarState();
      expect(RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(s), isTrue);
    });

    test('dos verificadores nunca son iguales', () {
      expect(generarVerificador(), isNot(generarVerificador()));
    });

    test('el desafío es de 43 caracteres y coincide con el ejemplo del RFC 7636', () {
      expect(desafioDe('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(desafioDe(generarVerificador()).length, 43);
    });
  });

  group('la dirección que se abre', () {
    test('lleva los cinco datos que lee /vincular/', () {
      final u = urlVincular(puerto: 51234, state: 'abc', desafio: 'd', idDispositivo: 'e', nombre: 'Caja 1 (mostrador)');
      expect(u.scheme, 'https');
      expect(u.host, 'horsepos.com');
      expect(u.path, '/vincular/');
      expect(u.queryParameters, {'port': '51234', 'state': 'abc', 'challenge': 'd', 'device': 'e', 'name': 'Caja 1 (mostrador)'});
    });
  });

  group('el aviso que vuelve al servidor local', () {
    test('con el state correcto devuelve el código', () {
      expect(codigoDeCallback(Uri.parse('/callback?code=xyz&state=ok'), stateEsperado: 'ok'), 'xyz');
    });

    test('con otro state, sin código o en otra ruta no devuelve nada', () {
      expect(codigoDeCallback(Uri.parse('/callback?code=xyz&state=otro'), stateEsperado: 'ok'), isNull);
      expect(codigoDeCallback(Uri.parse('/callback?state=ok'), stateEsperado: 'ok'), isNull);
      expect(codigoDeCallback(Uri.parse('/callback?code=&state=ok'), stateEsperado: 'ok'), isNull);
      expect(codigoDeCallback(Uri.parse('/otra?code=xyz&state=ok'), stateEsperado: 'ok'), isNull);
    });
  });
}
