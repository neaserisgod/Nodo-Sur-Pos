import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/vinculo_factura.dart';

/// Vincular las líneas de una factura con los productos del comercio. Las descripciones son las que Gemini leyó de la factura REAL de
/// Serra (2026-10-05): abreviadas ("ALF" por alfajor, "BL" por blanco), con el pack entre paréntesis y a veces cortadas.
void main() {
  const proveedor = 7;
  const catalogo = [
    ProductoCandidato(id: 1, nombre: 'Sal fina Dos Anclas 500g', proveedorId: proveedor),
    ProductoCandidato(id: 3, nombre: 'Alfajor Águila Minitorta Blanca 69g', proveedorId: proveedor),
    ProductoCandidato(id: 4, nombre: 'Alfajor Águila Minitorta Clásica 69g', proveedorId: proveedor),
    ProductoCandidato(id: 5, nombre: 'Alfajor Minitorta Brown 71g', proveedorId: proveedor),
    ProductoCandidato(id: 6, nombre: 'Alfajor Águila Minitorta Dark 69g', proveedorId: proveedor),
    ProductoCandidato(id: 7, nombre: 'Alfajor Chocotorta 71.5g', proveedorId: proveedor),
    ProductoCandidato(id: 8, nombre: 'Filtros Libella Slim 200', proveedorId: proveedor),
    ProductoCandidato(id: 9, nombre: 'Filtro Libella Extra Slim 200', proveedorId: proveedor),
    ProductoCandidato(id: 10, nombre: 'Coca Cola 2.25L'),
    ProductoCandidato(id: 11, nombre: 'Yerba Taragüí 1kg', codigoBarras: '7790387000013'),
  ];

  PropuestaDeVinculo vincular(String descripcion, {String? codigo, List<VinculoAprendido> vinculos = const [], List<ProductoCandidato> cat = catalogo}) =>
      proponerVinculos(
        lineas: [LineaAVincular(codigo: codigo, descripcion: descripcion)],
        catalogo: cat,
        vinculos: vinculos,
        proveedorId: proveedor,
      ).single;

  group('claves', () {
    test('el código se normaliza: sin ceros a la izquierda, sin símbolos, sin mayúsculas', () {
      expect(claveDeCodigo('00001421'), '1421');
      expect(claveDeCodigo(' AB-12/3 '), 'ab123');
      expect(claveDeCodigo(null), '');
      expect(claveDeCodigo('000'), '0');
    });

    test('la descripción se normaliza: sin pack, sin acentos, unidades parejas, sin ruido', () {
      expect(claveDeDescripcion('BG ALF AGUILA MINITORTA BL 69G(21)'), 'bg alf aguila minitorta bl 69g');
      expect(claveDeDescripcion('Alfajor Águila Minitorta Blanca 69 gr'), 'alfajor aguila minitorta blanca 69g');
      expect(claveDeDescripcion('BG ALF AGUILA MINITORTA DARK 69G (2'), 'bg alf aguila minitorta dark 69g');
      expect(claveDeDescripcion('Cerveza 473 cc'), 'cerveza 473ml');
      expect(claveDeDescripcion('Gaseosa 2,25 lts'), 'gaseosa 225l');
    });
  });

  group('lo que ya se aprendió del proveedor', () {
    test('un vínculo por código gana siempre, aunque el nombre no se parezca', () {
      final p = vincular(
        'ALGO RARO 123',
        codigo: '00001421',
        vinculos: const [VinculoAprendido(tipoClave: TipoClaveVinculo.codigo, clave: '1421', productoId: 1)],
      );
      expect(p.productoId, 1);
      expect(p.confianza, ConfianzaVinculo.alta);
      expect(p.origen, OrigenVinculo.aprendido);
    });

    test('lleva las unidades por cantidad que se aprendieron (un bulto de 6)', () {
      final p = vincular(
        'x',
        codigo: '55',
        vinculos: const [VinculoAprendido(tipoClave: TipoClaveVinculo.codigo, clave: '55', productoId: 3, unidadesPorCantidad: 6)],
      );
      expect(p.unidadesPorCantidad, 6);
    });

    test('si el código cambió, sirve el vínculo por descripción', () {
      final p = vincular(
        'BG ALF AGUILA MINITORTA BL 69G(21)',
        codigo: '99999999',
        vinculos: [VinculoAprendido(tipoClave: TipoClaveVinculo.descripcion, clave: claveDeDescripcion('BG ALF AGUILA MINITORTA BL 69G'), productoId: 3)],
      );
      expect(p.productoId, 3);
      expect(p.confianza, ConfianzaVinculo.alta);
    });

    test('un vínculo a un producto que ya no existe se ignora', () {
      final p = vincular(
        'BG ALF AGUILA MINITORTA BL 69G(21)',
        codigo: '1',
        vinculos: const [VinculoAprendido(tipoClave: TipoClaveVinculo.codigo, clave: '1', productoId: 999)],
      );
      expect(p.origen, isNot(OrigenVinculo.aprendido));
    });
  });

  group('código de barras', () {
    test('un código EAN de la factura que coincide con un producto lo vincula', () {
      final p = vincular('YERBA 1KG', codigo: '7790387000013');
      expect(p.productoId, 11);
      expect(p.confianza, ConfianzaVinculo.alta);
      expect(p.origen, OrigenVinculo.codigoDeBarras);
    });

    test('un código corto del proveedor no se confunde con un EAN', () {
      expect(vincular('YERBA 1KG', codigo: '1234').origen, isNot(OrigenVinculo.codigoDeBarras));
    });
  });

  group('parecido de nombre (abreviaturas de factura)', () {
    test('cada alfajor de Serra va a SU producto', () {
      expect(vincular('BG ALF AGUILA MINITORTA BL 69G(21)').productoId, 3);
      expect(vincular('BG ALF AGUILA MINITORTA CLAS 69G(21)').productoId, 4);
      expect(vincular('BG ALF MINITORTA BROWN 71G (21)').productoId, 5);
      expect(vincular('BG ALF AGUILA MINITORTA DARK 69G (2').productoId, 6);
      expect(vincular('BG ALF CHOCOTORTA 71.5G (21)').productoId, 7);
    });

    test('un parecido razonable pide confirmación (amarillo), no se da por seguro', () {
      final p = vincular('BG ALF AGUILA MINITORTA BL 69G(21)');
      expect(p.confianza, ConfianzaVinculo.media);
      expect(p.origen, OrigenVinculo.nombre);
    });

    test('Libella Slim y Libella Extra Slim no se confunden', () {
      expect(vincular('OP FILTROS LIBELLA SLIM X200 (20)').productoId, 8);
      expect(vincular('OP FILTRO LIBELLA EXTRA SLIM 200 (2').productoId, 9);
    });

    test('los tamaños tienen que ser iguales: 70g no es 69g', () {
      final p = vincular('BG ALF AGUILA MINITORTA BL 70G');
      expect(p.productoId == 3 && p.confianza == ConfianzaVinculo.media, isFalse);
    });

    test('un producto que no está en el catálogo queda sin vincular, sin inventar', () {
      final p = vincular('IMP ENCENDEDOR CANDELA TRANS 25U (4');
      expect(p.productoId, isNull);
      expect(p.confianza, ConfianzaVinculo.ninguna);
      expect(p.alternativas, isEmpty);
    });

    test('dos productos igual de parecidos: no elige, ofrece los dos', () {
      const doble = [
        ProductoCandidato(id: 20, nombre: 'Galletitas Surtidas 400g', proveedorId: 7),
        ProductoCandidato(id: 21, nombre: 'Galletitas Surtidas 400g', proveedorId: 7),
      ];
      final p = vincular('GALL SURTIDAS 400G', cat: doble);
      expect(p.confianza, ConfianzaVinculo.ninguna);
      expect(p.alternativas.toSet(), {20, 21});
    });

    test('a igual parecido, gana el producto del mismo proveedor', () {
      const dos = [
        ProductoCandidato(id: 30, nombre: 'Sal fina 500g', proveedorId: 99),
        ProductoCandidato(id: 31, nombre: 'Sal fina 500g', proveedorId: 7),
      ];
      final p = vincular('SAL FINA 500G', cat: dos);
      expect(p.productoId, 31);
    });

    test('ofrece alternativas ordenadas por parecido', () {
      final p = vincular('ALFAJOR MINITORTA 69G');
      expect(p.alternativas, isNotEmpty);
      expect(p.alternativas.first, anyOf(3, 4, 6));
    });
  });

  test('devuelve una propuesta por línea, en el mismo orden', () {
    final r = proponerVinculos(
      lineas: const [LineaAVincular(descripcion: 'BG ALF CHOCOTORTA 71.5G (21)'), LineaAVincular(descripcion: 'NADA QUE VER ZZZ')],
      catalogo: catalogo,
    );
    expect(r, hasLength(2));
    expect(r[0].productoId, 7);
    expect(r[1].productoId, isNull);
  });

  test('sin catálogo no hay propuestas pero no rompe', () {
    final r = proponerVinculos(lineas: const [LineaAVincular(descripcion: 'x')], catalogo: const []);
    expect(r.single.confianza, ConfianzaVinculo.ninguna);
  });
}
