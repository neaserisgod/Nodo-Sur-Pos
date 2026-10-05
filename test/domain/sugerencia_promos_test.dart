import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/sugerencia_promos.dart';

void main() {
  group('paresQueSeCompranJuntos', () {
    test('cuenta cuántas ventas llevaron los dos y calcula el lift', () {
      // 10 ventas: 1 y 2 juntos en 4; 1 solo en 2; 2 solo en 0; otras 4 sin ninguno.
      final ventas = [
        for (var i = 0; i < 4; i++) {1, 2},
        {1},
        {1},
        for (var i = 0; i < 4; i++) {9},
      ];
      final r = paresQueSeCompranJuntos(ventas, minVentasJuntos: 3, liftMinimoBp: 0);
      expect(r, hasLength(1));
      expect(r.single.productoA, 1);
      expect(r.single.productoB, 2);
      expect(r.single.ventasJuntos, 4);
      expect(r.single.ventasA, 6);
      expect(r.single.ventasB, 4);
      // 4 * 10 / (6 * 4) = 1,666… → 16666 bp (se trunca).
      expect(r.single.liftBp, 16666);
    });

    test('el orden de los ids no importa: siempre A < B', () {
      final r = paresQueSeCompranJuntos([
        {7, 3},
        {3, 7},
        {7, 3},
      ], minVentasJuntos: 3, liftMinimoBp: 0);
      expect(r.single.productoA, 3);
      expect(r.single.productoB, 7);
    });

    test('un par con pocas ventas juntas no se sugiere', () {
      final r = paresQueSeCompranJuntos([
        {1, 2},
        {1, 2},
        {1},
        {2},
      ], minVentasJuntos: 3, liftMinimoBp: 0);
      expect(r, isEmpty);
    });

    test('lo que se compra con todo (lift bajo) no se sugiere: la Coca va con cualquier cosa', () {
      // El producto 1 está en TODAS las ventas: comprarlo "junto" con el 2 no dice nada.
      final ventas = [
        for (var i = 0; i < 5; i++) {1, 2},
        for (var i = 0; i < 5; i++) {1},
      ];
      final r = paresQueSeCompranJuntos(ventas, minVentasJuntos: 3);
      expect(r, isEmpty);
    });

    test('solo cuentan los productos elegibles, pero el total de ventas incluye a todas', () {
      final ventas = [
        for (var i = 0; i < 4; i++) {1, 2, 99},
        for (var i = 0; i < 6; i++) {50},
      ];
      final r = paresQueSeCompranJuntos(ventas, elegibles: {1, 2}, minVentasJuntos: 3);
      expect(r.map((p) => (p.productoA, p.productoB)), [(1, 2)]);
    });

    test('un par que ya forma parte de una promo se saltea', () {
      final ventas = [
        for (var i = 0; i < 4; i++) {1, 2},
        for (var i = 0; i < 6; i++) {9},
      ];
      final r = paresQueSeCompranJuntos(ventas, minVentasJuntos: 3, promosExistentes: [
        {1, 2, 3},
      ]);
      expect(r, isEmpty);
    });

    test('ordena por ventas juntas y corta en el máximo', () {
      final ventas = [
        for (var i = 0; i < 5; i++) {1, 2},
        for (var i = 0; i < 8; i++) {3, 4},
        for (var i = 0; i < 4; i++) {5, 6},
        for (var i = 0; i < 20; i++) {9},
      ];
      final r = paresQueSeCompranJuntos(ventas, minVentasJuntos: 3, maximo: 2);
      expect(r.map((p) => p.ventasJuntos), [8, 5]);
    });

    test('una venta enorme (mayorista) no entra: no representa lo que lleva un cliente', () {
      final r = paresQueSeCompranJuntos([
        for (var i = 0; i < 5; i++) {for (var j = 0; j < 60; j++) j},
        for (var i = 0; i < 20; i++) {1000},
      ], minVentasJuntos: 3);
      expect(r, isEmpty);
    });

    test('sin ventas no hay sugerencias', () => expect(paresQueSeCompranJuntos(const []), isEmpty));
  });

  group('porcentajeSugeridoDePromoBp', () {
    test('regala más o menos la mitad de la ganancia de los sueltos, en saltos de 5 %', () {
      // costo 600, lista 1000 → ganancia de 40 % → promo al 20 %.
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 60000, precioListaCentavos: 100000), 2000);
      // costo 700, lista 1000 → 30 % → 15 %.
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 70000, precioListaCentavos: 100000), 1500);
    });

    test('con poca ganancia no hay promo posible (null)', () {
      // 15 % de ganancia → la mitad es 7,5 %, por debajo del piso de 10 %.
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 85000, precioListaCentavos: 100000), isNull);
    });

    test('sin ganancia, o con la lista por debajo del costo, null', () {
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 100000, precioListaCentavos: 100000), isNull);
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 120000, precioListaCentavos: 100000), isNull);
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 0, precioListaCentavos: 0), isNull);
    });

    test('tope de 40 %: una ganancia enorme no regala todo', () {
      expect(porcentajeSugeridoDePromoBp(costoCentavos: 10000, precioListaCentavos: 100000), 4000);
    });
  });
}
