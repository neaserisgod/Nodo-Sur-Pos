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

  test('una dirección de OTRO sitio (aunque sea https) se descarta: el APK y su hash tienen que venir de horsepos.com', () {
    for (final host in ['evil.example.com', 'horsepos.com.evil.io', 'xhorsepos.com', 'horsepos.com@evil.io']) {
      expect(
        ofertaDeRespuesta('{"update":true,"version":"1.0.0+1","url":"https://$host/api/update/file?id=7","sha256":"$sha"}'),
        isNull,
        reason: host,
      );
    }
  });

  test('el hash tiene que ser un SHA-256 en hexadecimal: 64 caracteres cualquiera no alcanzan', () {
    expect(
      ofertaDeRespuesta('{"update":true,"version":"1.0.0+1","url":"https://horsepos.com/api/update/file?id=7","sha256":"${'z' * 64}"}'),
      isNull,
    );
    expect(
      ofertaDeRespuesta('{"update":true,"version":"1.0.0+1","url":"https://horsepos.com/api/update/file?id=7","sha256":"${'A' * 64}"}'),
      isNotNull,
      reason: 'las mayúsculas se aceptan (se pasan a minúsculas antes de comparar)',
    );
  });
}
