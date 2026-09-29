import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/markup.dart';

void main() {
  group('precioDesdeCostoYMarkup', () {
    test('costo 1000 + markup 70% → precio 1700 (ya es peso exacto)', () {
      expect(precioDesdeCostoYMarkup(1000, 7000), 1700);
    });

    test('costo 1000 + markup 5% → 1050 centavos exactos, redondea a 1100', () {
      // A diferencia del sistema de referencia (que deja 1050), acá el
      // negocio no maneja centavos: 1050 no es un peso entero.
      expect(precioDesdeCostoYMarkup(1000, 500), 1100);
    });

    test('costo 0 + markup 0% → precio 0', () {
      expect(precioDesdeCostoYMarkup(0, 0), 0);
    });

    test('lanza error si markupBp <= -10000 (división por cero o negativa)', () {
      expect(() => precioDesdeCostoYMarkup(1000, -10000), throwsArgumentError);
    });
  });

  group('costoDesdePrecioYMarkup', () {
    test('precio 1700 + markup 70% → costo 1000 (ya es peso exacto)', () {
      expect(costoDesdePrecioYMarkup(1700, 7000), 1000);
    });

    test('precio 1050 + markup 5% → 1000 centavos exactos, ya es peso entero', () {
      expect(costoDesdePrecioYMarkup(1050, 500), 1000);
    });

    test('precio 1000 + markup 3% → costo exacto 970,87..., redondea a 1000', () {
      // 1000*10000/10300 = 970.87... centavos → sube al próximo peso: 1000
      expect(costoDesdePrecioYMarkup(1000, 300), 1000);
    });

    test('lanza error si markupBp <= -10000', () {
      expect(() => costoDesdePrecioYMarkup(1000, -10000), throwsArgumentError);
    });
  });

  group('markupBpDesdeCostoYPrecio — margen en vivo (Regla 14)', () {
    test('costo 1000, precio 1700 → 7000 bp (70%)', () {
      expect(markupBpDesdeCostoYPrecio(1000, 1700), 7000);
    });

    test('costo 1000, precio 1050 → 500 bp (5%)', () {
      expect(markupBpDesdeCostoYPrecio(1000, 1050), 500);
    });

    test('margen negativo cuando el costo subió y el precio no se tocó', () {
      // Caso real descrito en Regla 5: el costo real sube, el precio queda
      // atrás. El margen negativo se muestra, no se oculta.
      expect(markupBpDesdeCostoYPrecio(1000, 800), -2000);
    });

    test('precio igual al costo → margen 0', () {
      expect(markupBpDesdeCostoYPrecio(1000, 1000), 0);
    });

    test('lanza error si el costo es 0: no hay margen infinito silencioso', () {
      expect(() => markupBpDesdeCostoYPrecio(0, 1000), throwsArgumentError);
    });
  });

  group('gananciaBruta — usa valores-foto (Regla 4, costo-foto)', () {
    test('precio 1700, costo 1000, cantidad 3 → ganancia 2100', () {
      expect(gananciaBruta(1700, 1000, 3), 2100);
    });

    test('precio = costo → ganancia 0', () {
      expect(gananciaBruta(1000, 1000, 5), 0);
    });

    test('margen negativo → ganancia negativa, no se trunca a 0', () {
      expect(gananciaBruta(800, 1000, 2), -400);
    });

    test('un aumento de costo posterior no reescribe la ganancia histórica', () {
      // La línea de venta guarda precio y costo del momento (Regla 4).
      const precioFoto = 1120000;
      const costoFoto = 800000;
      const costoActualDelProducto = 950000; // subió después de la venta

      final gananciaHistorica = gananciaBruta(precioFoto, costoFoto, 1);
      final gananciaSiUsaraCostoActual = gananciaBruta(precioFoto, costoActualDelProducto, 1);

      expect(gananciaHistorica, 320000);
      expect(gananciaSiUsaraCostoActual, 170000);
      expect(gananciaHistorica, isNot(gananciaSiUsaraCostoActual));
    });
  });

  group('precioConMarkupACentena — porcentaje del proveedor, redondeo a la próxima centena', () {
    test('costo \$1.000 con 30% cae justo en centena: \$1.300, no sube', () {
      expect(precioConMarkupACentena(100000, 3000), 130000);
    });

    test('costo \$1.030 con 30% = \$1.339 sube a \$1.400', () {
      expect(precioConMarkupACentena(103000, 3000), 140000);
    });

    test('un peso por encima de una centena sube a la siguiente', () {
      // 100.01 pesos de costo con 0% = \$100,01 → \$200.
      expect(precioConMarkupACentena(10001, 0), 20000);
      expect(precioConMarkupACentena(10000, 0), 10000);
    });

    test('con 100% duplica y redondea (\$1.250 → \$2.500)', () {
      expect(precioConMarkupACentena(125000, 10000), 250000);
    });

    test('un costo chico siempre da al menos \$100 (nunca \$0)', () {
      expect(precioConMarkupACentena(500, 3000), 10000);
    });

    test('no usa doubles: un caso que en punto flotante caería del lado equivocado', () {
      // 0.29 * 100 en double es 28.999999999999996: con enteros da exacto.
      expect(precioConMarkupACentena(29000, 3000), 40000); // \$290 * 1,3 = \$377 → \$400
    });
  });

  group('precioDePromo — costo + porcentaje, nunca más que el precio de lista', () {
    test('cuando el porcentaje no llega a la lista, gana el porcentaje', () {
      // Costos 1.000 + 500 = 1.500; +30% = 1.950 → 2.000; lista 1.400 + 900 = 2.300.
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 230000, markupBp: 3000);
      expect(r.precioCentavos, 200000);
      expect(r.topeadoPorLista, false);
    });

    test('si el porcentaje pasa la lista, queda en la lista (tope)', () {
      // 1.500 * 1,5 = 2.250 → 2.300, pero la lista suma 2.100: tope.
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 210000, markupBp: 5000);
      expect(r.precioCentavos, 210000);
      expect(r.topeadoPorLista, true);
    });

    test('el tope va después del redondeo: 2.250 no se redondea a 2.300 si la lista es 2.290', () {
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 229000, markupBp: 5000);
      expect(r.precioCentavos, 229000);
      expect(r.topeadoPorLista, true);
    });

    test('igual a la lista no es tope', () {
      final r = precioDePromo(costoTotalCentavos: 100000, precioListaTotalCentavos: 130000, markupBp: 3000);
      expect(r.precioCentavos, 130000);
      expect(r.topeadoPorLista, false);
    });
  });
}
