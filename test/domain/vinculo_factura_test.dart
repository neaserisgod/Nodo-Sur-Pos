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

  group('resumen de vínculos (el "reconocí 8 de 10")', () {
    const aprendido = PropuestaDeVinculo(productoId: 1, confianza: ConfianzaVinculo.alta, origen: OrigenVinculo.aprendido);
    const porEan = PropuestaDeVinculo(productoId: 2, confianza: ConfianzaVinculo.alta, origen: OrigenVinculo.codigoDeBarras);
    const porNombre = PropuestaDeVinculo(productoId: 3, confianza: ConfianzaVinculo.media, origen: OrigenVinculo.nombre);
    const porIa = PropuestaDeVinculo(productoId: 4, confianza: ConfianzaVinculo.media, origen: OrigenVinculo.ia);
    const nada = PropuestaDeVinculo(confianza: ConfianzaVinculo.ninguna);

    test('aprendido y código de barras son seguros; nombre e IA, para confirmar; sin producto, sin vincular', () {
      expect(estadoDeVinculo(aprendido, 1), EstadoDeVinculo.seguro);
      expect(estadoDeVinculo(porEan, 2), EstadoDeVinculo.seguro);
      expect(estadoDeVinculo(porNombre, 3), EstadoDeVinculo.aConfirmar);
      expect(estadoDeVinculo(porIa, 4), EstadoDeVinculo.aConfirmar);
      expect(estadoDeVinculo(nada, null), EstadoDeVinculo.sinVincular);
    });

    test('un producto elegido a mano queda para confirmar, aunque la propuesta fuera segura', () {
      expect(estadoDeVinculo(aprendido, 99), EstadoDeVinculo.aConfirmar);
      expect(estadoDeVinculo(nada, 5), EstadoDeVinculo.aConfirmar);
    });

    test('si el dueño borra el producto, vuelve a sin vincular', () {
      expect(estadoDeVinculo(aprendido, null), EstadoDeVinculo.sinVincular);
    });

    test('cuenta cada estado', () {
      final r = resumenDeVinculos([aprendido, porEan, porNombre, porIa, nada], [1, 2, 3, 4, null]);
      expect(r, {EstadoDeVinculo.seguro: 2, EstadoDeVinculo.aConfirmar: 2, EstadoDeVinculo.sinVincular: 1});
    });
  });

  /// Un mismo CUIT para dos proveedores del comercio (El dueño, 2026-10-07: "Proveedor X me trae cosas varias y también cigarrillos,
  /// yo lo tengo diferenciado como X cigarrillos"): la factura se asigna por lo que trae, no por el CUIT solo.
  group('elegirProveedorDeFactura', () {
    const varios = 20, cigarrillos = 21;
    const cat = [
      ProductoCandidato(id: 100, nombre: 'Galletitas Oreo 118g', proveedorId: varios),
      ProductoCandidato(id: 101, nombre: 'Jugo Tang Naranja 18g', proveedorId: varios),
      ProductoCandidato(id: 200, nombre: 'Marlboro Box 20', proveedorId: cigarrillos),
      ProductoCandidato(id: 201, nombre: 'Philip Morris Box 20', proveedorId: cigarrillos),
    ];
    const lineasCigarrillos = [LineaAVincular(descripcion: 'MARLBORO BOX 20'), LineaAVincular(descripcion: 'PHILIP MORRIS BOX 20')];
    const lineasVarios = [LineaAVincular(descripcion: 'GALLETITAS OREO 118G'), LineaAVincular(descripcion: 'JUGO TANG NARANJA 18G')];

    int? elegir(List<LineaAVincular> lineas, {List<int> candidatos = const [varios, cigarrillos], Map<int, List<VinculoAprendido>> vinculos = const {}}) =>
        elegirProveedorDeFactura(candidatos: candidatos, lineas: lineas, catalogo: cat, vinculosPorProveedor: vinculos);

    test('sin candidatos no hay proveedor, y con uno solo es ese (lo de siempre)', () {
      expect(elegir(lineasCigarrillos, candidatos: const []), isNull);
      expect(elegir(lineasCigarrillos, candidatos: const [varios]), varios);
    });

    test('con dos proveedores para el CUIT, gana el dueño de los productos que trae la factura', () {
      expect(elegir(lineasCigarrillos), cigarrillos);
      expect(elegir(lineasVarios), varios);
    });

    test('lo aprendido de un proveedor pesa más que el parecido de nombre', () {
      final vinculos = {
        cigarrillos: [
          VinculoAprendido(tipoClave: TipoClaveVinculo.descripcion, clave: claveDeDescripcion('MRL BX 20 KS'), productoId: 200, unidadesPorCantidad: 10),
          VinculoAprendido(tipoClave: TipoClaveVinculo.descripcion, clave: claveDeDescripcion('PM BX 20 KS'), productoId: 201, unidadesPorCantidad: 10),
        ],
      };
      const abreviadas = [LineaAVincular(descripcion: 'MRL BX 20 KS'), LineaAVincular(descripcion: 'PM BX 20 KS'), LineaAVincular(descripcion: 'GALLETITAS OREO 118G')];
      expect(elegir(abreviadas, vinculos: vinculos), cigarrillos);
    });

    test('empate o nada reconocido: no adivina, devuelve null para que se pregunte', () {
      expect(elegir(const [LineaAVincular(descripcion: 'MARLBORO BOX 20'), LineaAVincular(descripcion: 'GALLETITAS OREO 118G')]), isNull);
      expect(elegir(const [LineaAVincular(descripcion: 'PRODUCTO DESCONOCIDO XYZ')]), isNull);
    });
  });

  group('producto nuevo desde una línea (El dueño, 2026-10-07)', () {
    test('el nombre sale sin el código del proveedor ni el pack, con mayúscula por palabra', () {
      expect(nombreSugeridoDesdeFactura('1042 - CREMA SIMPLE X 200 GR (24)'), 'Crema Simple X 200 gr');
      expect(nombreSugeridoDesdeFactura('BG ALF AGUILA MINITORTA DARK 69G (2'), 'Bg Alf Aguila Minitorta Dark 69g');
      expect(nombreSugeridoDesdeFactura('  XB   CONVERTIBLE BOX  '), 'Xb Convertible Box');
    });

    test('las abreviaturas se expanden con las palabras de tus productos, con su acento', () {
      const nombres = ['Alfajor Águila Minitorta Blanca 69g', 'Alfajor Águila Minitorta Clásica 69g', 'Alfajor Minitorta Brown 71g'];
      expect(
        nombreSugeridoDesdeFactura('BG ALF AGUILA MINITORTA BL 69G (2', nombresDelCatalogo: nombres),
        'Bg Alfajor Águila Minitorta Blanca 69g',
      );
      expect(nombreSugeridoDesdeFactura('ALF CLAS 69G', nombresDelCatalogo: nombres), 'Alfajor Clásica 69g');
    });

    test('con dos palabras posibles parecidas no adivina, salvo que una aparezca el doble', () {
      expect(nombreSugeridoDesdeFactura('YOGUR BL', nombresDelCatalogo: const ['Yogur Blanco', 'Queso Blanca']), 'Yogur Bl');
      expect(
        nombreSugeridoDesdeFactura('YOGUR BL', nombresDelCatalogo: const ['Yogur Blanco', 'Leche Blanco', 'Queso Blanca']),
        'Yogur Blanco',
      );
    });

    test('un catálogo en mayúsculas no impone mayúsculas', () {
      expect(nombreSugeridoDesdeFactura('GALL OREO', nombresDelCatalogo: const ['GALLETITAS OREO 118G']), 'Galletitas Oreo');
    });

    test('solo un código con forma de código de barras se usa como tal', () {
      expect(codigoDeBarrasDeLinea('7790387000013'), '7790387000013');
      expect(codigoDeBarrasDeLinea('1042'), isNull);
      expect(codigoDeBarrasDeLinea('AB-7790387000013'), isNull);
      expect(codigoDeBarrasDeLinea(null), isNull);
    });
  });
}
