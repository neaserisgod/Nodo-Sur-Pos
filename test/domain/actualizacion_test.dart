import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/actualizacion.dart';

void main() {
  group('separarVersion', () {
    // package_info_plus en Windows parte ProductVersion por '+'. Con
    // ProductVersion "1.0.0.2098" (lo que exige WinSparkle) devuelve la
    // versión entera en `version` y el build vacío.
    test('ya separado (Android, o Windows con "+") queda igual', () {
      expect(separarVersion('1.0.0', '2098'), (nombre: '1.0.0', build: '2098'));
    });

    test('Windows con ProductVersion de cuatro segmentos', () {
      expect(separarVersion('1.0.0.2098', ''), (nombre: '1.0.0', build: '2098'));
    });

    test('con "+" y sin build aparte', () {
      expect(separarVersion('1.0.0+2098', ''), (nombre: '1.0.0', build: '2098'));
    });

    test('sin build queda el nombre solo', () {
      expect(separarVersion('1.0.0', ''), (nombre: '1.0.0', build: ''));
    });
  });

  group('versionParaFeed', () {
    test('une nombre y build con punto, como lo emite el servidor', () {
      expect(versionParaFeed('1.0.0', '2098'), '1.0.0.2098');
    });

    test('sin build queda el nombre solo', () {
      expect(versionParaFeed('1.0.0', ''), '1.0.0');
    });
  });

  group('compararVersiones', () {
    // Mismos casos que el spike contra WinSparkle 0.8.1 (DECISIONES.md): el
    // build mayor ofrece, el igual y el menor no.
    test('mismo build es igual', () {
      expect(compararVersiones('1.0.0.2098', '1.0.0.2098'), 0);
    });

    test('build mayor es mayor, menor es menor', () {
      expect(compararVersiones('1.0.0.2099', '1.0.0.2098'), greaterThan(0));
      expect(compararVersiones('1.0.0.2097', '1.0.0.2098'), lessThan(0));
    });

    test('compara números, no texto (10000 > 9999)', () {
      expect(compararVersiones('1.0.0.10000', '1.0.0.9999'), greaterThan(0));
    });

    test('un segmento de nombre mayor gana sobre el build', () {
      expect(compararVersiones('1.0.1.1', '1.0.0.2098'), greaterThan(0));
    });

    test('segmentos que faltan valen cero', () {
      expect(compararVersiones('1.0.0', '1.0.0.0'), 0);
      expect(compararVersiones('1.0.0', '1.0.0.2098'), lessThan(0));
    });

    test('el "+" separa igual que el punto', () {
      expect(compararVersiones('1.0.0+2098', '1.0.0.2098'), 0);
    });
  });

  group('versionMasNuevaDelFeed', () {
    String feed(List<String> versiones) =>
        '''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
${versiones.map((v) => '<item><enclosure url="https://x/y.exe" sparkle:version="$v" sparkle:os="windows" length="0" type="application/octet-stream"/></item>').join('\n')}
</channel></rss>''';

    test('lee sparkle:version del enclosure', () {
      expect(versionMasNuevaDelFeed(feed(['1.0.0.2099'])), '1.0.0.2099');
    });

    test('con varios items devuelve la mayor, sin importar el orden', () {
      expect(
        versionMasNuevaDelFeed(feed(['1.0.0.2099', '1.0.0.2100', '1.0.0.2098'])),
        '1.0.0.2100',
      );
    });

    test('lee también la forma de elemento', () {
      const xml =
          '<rss><channel><item><sparkle:version>1.0.0.2101</sparkle:version></item></channel></rss>';
      expect(versionMasNuevaDelFeed(xml), '1.0.0.2101');
    });

    test('feed vacío o sin versiones devuelve null', () {
      expect(versionMasNuevaDelFeed(''), isNull);
      expect(versionMasNuevaDelFeed('<rss><channel></channel></rss>'), isNull);
    });

    test('basura que no es un feed no rompe', () {
      expect(versionMasNuevaDelFeed('<html>502 Bad Gateway</html>'), isNull);
    });
  });

  group('hayActualizacion', () {
    String feed(String v) => '<enclosure sparkle:version="$v" />';

    test('ofrece solo si el feed es estrictamente mayor', () {
      expect(hayActualizacion(versionActual: '1.0.0.2098', xmlFeed: feed('1.0.0.2099')), isTrue);
      expect(hayActualizacion(versionActual: '1.0.0.2098', xmlFeed: feed('1.0.0.2098')), isFalse);
      expect(hayActualizacion(versionActual: '1.0.0.2098', xmlFeed: feed('1.0.0.2097')), isFalse);
    });

    test('sin versión en el feed no hay actualización', () {
      expect(hayActualizacion(versionActual: '1.0.0.2098', xmlFeed: ''), isFalse);
    });
  });

  group('urlFeedActualizaciones', () {
    test('arma la URL con plataforma, canal y cid', () {
      expect(
        urlFeedActualizaciones(idCliente: 'abc123'),
        'https://horsepos.com/api/update/appcast.xml?platform=windows&channel=stable&cid=abc123',
      );
    });

    test('escapa un cid raro en vez de romper la URL', () {
      final url = urlFeedActualizaciones(idCliente: 'a b&c');
      expect(Uri.parse(url).queryParameters['cid'], 'a b&c');
    });
  });

  group('decidirAviso', () {
    final ahora = DateTime(2026, 9, 30, 12);

    test('sin actualización no hay aviso', () {
      expect(
        decidirAviso(hayActualizacion: false, hayVentaAbierta: false, ahora: ahora),
        AvisoActualizacion.ninguno,
      );
    });

    test('con actualización y sin venta abierta se avisa', () {
      expect(
        decidirAviso(hayActualizacion: true, hayVentaAbierta: false, ahora: ahora),
        AvisoActualizacion.mostrar,
      );
    });

    test('con venta abierta nunca se muestra nada', () {
      expect(
        decidirAviso(hayActualizacion: true, hayVentaAbierta: true, ahora: ahora),
        AvisoActualizacion.ninguno,
      );
    });

    test('"más tarde" silencia hasta que vence la postergación', () {
      final hasta = ahora.add(const Duration(hours: 4));
      expect(
        decidirAviso(
          hayActualizacion: true,
          hayVentaAbierta: false,
          postergadaHasta: hasta,
          ahora: ahora,
        ),
        AvisoActualizacion.ninguno,
      );
      expect(
        decidirAviso(
          hayActualizacion: true,
          hayVentaAbierta: false,
          postergadaHasta: hasta,
          ahora: hasta,
        ),
        AvisoActualizacion.mostrar,
      );
    });
  });
}
