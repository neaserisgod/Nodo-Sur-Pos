import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_sugerencia_promos.dart';
import 'package:la_plazoleta/domain/sugerencia_promos.dart';
import 'package:la_plazoleta/servicios/asistente_promos.dart';
import 'package:la_plazoleta/servicios/gemini.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late SugerenciaDePromo sugerencia;

  setUp(() async {
    db = baseDeTest();
    Future<Producto> crear(String nombre, int costo, int precio) async {
      final id = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: nombre, costoCentavos: Value(costo), precioCentavos: Value(precio)));
      return (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    }

    final yerba = await crear('Yerba', 100000, 140000);
    final galletitas = await crear('Galletitas', 50000, 90000);
    sugerencia = SugerenciaDePromo(
      par: ParSugerido(productoA: yerba.id, productoB: galletitas.id, ventasJuntos: 7, ventasA: 10, ventasB: 12, liftBp: 20000),
      componentes: [ComponenteDePromo(producto: yerba, cantidad: 1), ComponenteDePromo(producto: galletitas, cantidad: 1)],
      porcentajeBp: 1500,
      calculo: const PrecioDePromoCalculado(costoCentavos: 150000, listaCentavos: 230000, precioCentavos: 180000, topeadoPorLista: false),
    );
  });
  tearDown(() => db.close());

  test('el pedido lleva solo nombres y números, uno por combo', () {
    final pedido = armarPedidoDePromos([sugerencia]);
    expect(pedido, contains('0) Yerba + Galletitas'));
    expect(pedido, contains('7 ventas'));
  });

  group('leerTextosDePromos', () {
    test('lee cada entrada por su posición', () {
      final r = leerTextosDePromos({
        'promos': [
          {'i': 1, 'nombre': ' Merienda Dulce ', 'motivo': 'Van juntos seguido.'},
          {'i': 0, 'nombre': 'Combo Mate', 'motivo': 'Se piden juntos.'},
        ],
      }, 2);
      expect(r[0]!.nombre, 'Combo Mate');
      expect(r[1]!.nombre, 'Merienda Dulce');
    });

    test('lo roto o fuera de rango queda en null, sin tirar', () {
      final r = leerTextosDePromos({
        'promos': [
          {'i': 5, 'nombre': 'Fuera', 'motivo': 'x'},
          {'i': 0, 'nombre': '', 'motivo': 'x'},
          {'i': 1, 'nombre': 'Sin motivo'},
          'basura',
        ],
      }, 2);
      expect(r, [null, null]);
    });

    test('una respuesta que no tiene la forma esperada deja todo en null', () {
      expect(leerTextosDePromos('hola', 2), [null, null]);
      expect(leerTextosDePromos({'otra': 1}, 2), [null, null]);
      expect(leerTextosDePromos(null, 1), [null]);
    });

    test('un nombre largo se corta', () {
      final r = leerTextosDePromos({
        'promos': [
          {'i': 0, 'nombre': 'A' * 100, 'motivo': 'x'},
        ],
      }, 1);
      expect(r[0]!.nombre.length, maximoLargoNombreDePromo);
    });
  });

  test('redactarPromos usa a Gemini y devuelve los textos', () async {
    final cliente = ClienteGemini(
      apiKey: 'k',
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"promos":[{"i":0,"nombre":"Merienda","motivo":"Van juntos."}]}'},
                    ],
                  },
                },
              ],
            }),
            200,
          )),
    );
    final r = await redactarPromos(cliente, [sugerencia]);
    expect(r.single!.nombre, 'Merienda');
  });

  test('sin sugerencias no llama a Gemini', () async {
    final cliente = ClienteGemini(apiKey: 'k', client: MockClient((_) async => fail('no tenía que llamar')));
    expect(await redactarPromos(cliente, const []), isEmpty);
  });
}
