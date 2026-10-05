import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/domain/vinculo_factura.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import 'package:la_plazoleta/servicios/vinculador_ia.dart';

String _respuesta(String json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': json},
            ],
          },
        },
      ],
    });

void main() {
  const catalogo = [
    ProductoCandidato(id: 1, nombre: 'Alfajor Águila Minitorta Blanca 69g', proveedorId: 7),
    ProductoCandidato(id: 2, nombre: 'Alfajor Águila Minitorta Dark 69g', proveedorId: 7),
    ProductoCandidato(id: 3, nombre: 'Coca Cola 2.25L', proveedorId: 9),
    ProductoCandidato(id: 4, nombre: 'Galletitas surtidas', proveedorId: 9),
  ];
  const pendientes = [
    (posicion: 0, linea: LineaAVincular(codigo: '19615', descripcion: 'BG ALF AGUILA MINITORTA BL 69G(21)')),
    (posicion: 3, linea: LineaAVincular(descripcion: 'BG ALF AGUILA MINITORTA DARK 69G (2')),
  ];

  group('candidatosParaIa', () {
    test('trae los del proveedor y las alternativas que ofreció el parecido de nombre', () {
      final c = candidatosParaIa(
        catalogo,
        7,
        const [PropuestaDeVinculo(confianza: ConfianzaVinculo.ninguna, alternativas: [4])],
      );
      expect(c.map((x) => x.id), [1, 2, 4]);
    });

    test('sin proveedor, solo las alternativas', () {
      final c = candidatosParaIa(catalogo, null, const [PropuestaDeVinculo(confianza: ConfianzaVinculo.ninguna, alternativas: [3])]);
      expect(c.map((x) => x.id), [3]);
    });

    test('no pasa de un máximo', () {
      final muchos = [for (var i = 0; i < 1000; i++) ProductoCandidato(id: i, nombre: 'p$i', proveedorId: 7)];
      expect(candidatosParaIa(muchos, 7, const []), hasLength(maximoCandidatosParaIa));
    });
  });

  test('el pedido lleva solo descripciones, códigos de la factura y nombres con su id: ni precios ni costos', () {
    final pedido = armarPedidoDeVinculos(pendientes, catalogo.take(2).toList());
    expect(pedido, contains('0) [19615] BG ALF AGUILA MINITORTA BL 69G(21)'));
    expect(pedido, contains('3) BG ALF AGUILA MINITORTA DARK 69G (2'));
    expect(pedido, contains('1: Alfajor Águila Minitorta Blanca 69g'));
    expect(pedido, isNot(contains('\$')));
  });

  group('leerVinculosDeIa', () {
    final presentados = {1, 2};
    final pedidas = {0, 3};

    test('lee las posiciones y los ids', () {
      final r = leerVinculosDeIa(
        {
          'vinculos': [
            {'i': 0, 'producto_id': 1, 'motivo': 'x'},
            {'i': 3, 'producto_id': 2},
          ],
        },
        posicionesPedidas: pedidas,
        idsPresentados: presentados,
      );
      expect(r, {0: 1, 3: 2});
    });

    test('un id que no estaba en la lista (inventado) se descarta', () {
      final r = leerVinculosDeIa(
        {
          'vinculos': [
            {'i': 0, 'producto_id': 999},
          ],
        },
        posicionesPedidas: pedidas,
        idsPresentados: presentados,
      );
      expect(r, isEmpty);
    });

    test('una posición que no se pidió se descarta; null y basura también', () {
      final r = leerVinculosDeIa(
        {
          'vinculos': [
            {'i': 5, 'producto_id': 1},
            {'i': 0, 'producto_id': null},
            'basura',
            {'i': 'cero', 'producto_id': 1},
          ],
        },
        posicionesPedidas: pedidas,
        idsPresentados: presentados,
      );
      expect(r, isEmpty);
    });

    test('una respuesta con otra forma no rompe', () {
      for (final j in <Object?>[null, 'hola', {'otra': 1}, {'vinculos': 3}]) {
        expect(leerVinculosDeIa(j, posicionesPedidas: pedidas, idsPresentados: presentados), isEmpty);
      }
    });
  });

  group('vincularConIa', () {
    test('le pide a Gemini y devuelve lo válido', () async {
      final cliente = ClienteGemini(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(_respuesta('{"vinculos":[{"i":0,"producto_id":1},{"i":3,"producto_id":2}]}'), 200)),
      );
      final r = await vincularConIa(cliente, pendientes: pendientes, candidatos: catalogo.take(2).toList());
      expect(r, {0: 1, 3: 2});
    });

    test('sin líneas o sin candidatos no llama a Google', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => fail('no tenía que llamar a Google')));
      expect(await vincularConIa(cliente, pendientes: const [], candidatos: catalogo), isEmpty);
      expect(await vincularConIa(cliente, pendientes: pendientes, candidatos: const []), isEmpty);
    });

    test('un error de Gemini se propaga para que el que llama decida', () async {
      final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => http.Response('{}', 429)));
      await expectLater(vincularConIa(cliente, pendientes: pendientes, candidatos: catalogo), throwsA(isA<ErrorGemini>()));
    });
  });

  group('conSugerenciasDeIa', () {
    const ninguna = PropuestaDeVinculo(confianza: ConfianzaVinculo.ninguna, alternativas: [1, 2]);
    const aprendida = PropuestaDeVinculo(productoId: 2, confianza: ConfianzaVinculo.alta, origen: OrigenVinculo.aprendido);
    final ids = {1, 2, 3};

    test('una línea sin vincular toma la sugerencia, en amarillo y con origen IA', () {
      final r = conSugerenciasDeIa([ninguna], {0: 1}, idsDelCatalogo: ids).single;
      expect(r.productoId, 1);
      expect(r.confianza, ConfianzaVinculo.media);
      expect(r.origen, OrigenVinculo.ia);
      expect(r.alternativas, [2]);
    });

    test('lo ya vinculado con confianza alta no se toca', () {
      expect(conSugerenciasDeIa([aprendida], {0: 1}, idsDelCatalogo: ids).single.productoId, 2);
    });

    test('un id que no existe en el catálogo se ignora', () {
      expect(conSugerenciasDeIa([ninguna], {0: 99}, idsDelCatalogo: ids).single.productoId, isNull);
    });
  });
}
