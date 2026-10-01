import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/actualizacion.dart';

void main() {
  final sha = 'a' * 64;

  test('respuesta con actualización: arma la oferta', () {
    final o = ofertaDeRespuesta(
      '{"update":true,"version":"1.0.0+2101","url":"https://horsepos.com/api/update/file?id=7","sha256":"$sha"}',
    );
    expect(o, isNotNull);
    expect(o!.version, '1.0.0+2101');
    expect(o.url.host, 'horsepos.com');
    expect(o.sha256, sha);
  });

  test('sin actualización: null', () {
    expect(ofertaDeRespuesta('{"update":false}'), isNull);
  });

  test('url que no es https o hash mal formado: se descarta', () {
    expect(
      ofertaDeRespuesta('{"update":true,"version":"1.0.0+1","url":"http://x/y","sha256":"$sha"}'),
      isNull,
    );
    expect(
      ofertaDeRespuesta('{"update":true,"version":"1.0.0+1","url":"https://x/y","sha256":"abc"}'),
      isNull,
    );
  });
}
