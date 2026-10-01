import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/ganancia.dart';

void main() {
  group('precioDesdeCostoYGanancia — ganancia sobre el precio', () {
    test('costo 700 con 30% de ganancia → precio 1000 (ya es peso exacto)', () {
      expect(precioDesdeCostoYGanancia(70000, 3000), 100000);
    });

    test('costo 1000 con 30% → 1428,57 exacto, sube al peso: 1429', () {
      // No es 1300: eso sería 30% de recargo sobre el costo (markup), que
      // deja solo 23,08% de ganancia real.
      expect(precioDesdeCostoYGanancia(100000, 3000), 142900);
    });

    test('con 50% de ganancia el precio es el doble del costo', () {
      expect(precioDesdeCostoYGanancia(100000, 5000), 200000);
    });

    test('costo 0 con 0% → precio 0', () {
      expect(precioDesdeCostoYGanancia(0, 0), 0);
    });

    test('0% de ganancia deja el precio igual al costo', () {
      expect(precioDesdeCostoYGanancia(100000, 0), 100000);
    });

    test('lanza error con 100% o más de ganancia (precio infinito)', () {
      expect(() => precioDesdeCostoYGanancia(1000, 10000), throwsArgumentError);
      expect(() => precioDesdeCostoYGanancia(1000, 12000), throwsArgumentError);
    });
  });

  group('costoDesdePrecioYGanancia', () {
    test('precio 1000 con 30% de ganancia → costo 700', () {
      expect(costoDesdePrecioYGanancia(100000, 3000), 70000);
    });

    test('precio 1000 con 3% → costo exacto 970, ya es peso entero', () {
      expect(costoDesdePrecioYGanancia(100000, 300), 97000);
    });

    test('precio 1001 con 33,33% → 667,37 exacto, sube al peso: 668', () {
      expect(costoDesdePrecioYGanancia(100100, 3333), 66800);
    });

    test('lanza error con 100% o más de ganancia', () {
      expect(() => costoDesdePrecioYGanancia(1000, 10000), throwsArgumentError);
    });
  });

  group('gananciaBpDesdeCostoYPrecio — ganancia en vivo (Regla 14)', () {
    test('costo 700, precio 1000 → 3000 bp (30%)', () {
      expect(gananciaBpDesdeCostoYPrecio(70000, 100000), 3000);
    });

    test('costo 1000, precio 1700 → 4118 bp (41,18%), no 70%', () {
      // Los mismos números dan 70% de markup sobre el costo; la ganancia real
      // sobre lo que se cobra es (1700 − 1000) / 1700.
      expect(gananciaBpDesdeCostoYPrecio(100000, 170000), 4118);
    });

    test('ida y vuelta: el precio que da un 40% muestra 40%', () {
      final precio = precioDesdeCostoYGanancia(60000, 4000);
      expect(precio, 100000);
      expect(gananciaBpDesdeCostoYPrecio(60000, precio), 4000);
    });

    test('ganancia negativa cuando el costo subió y el precio no se tocó', () {
      // Caso real descrito en Regla 5: el costo real sube, el precio queda
      // atrás. La ganancia negativa se muestra, no se oculta.
      expect(gananciaBpDesdeCostoYPrecio(100000, 80000), -2500);
    });

    test('precio igual al costo → ganancia 0', () {
      expect(gananciaBpDesdeCostoYPrecio(100000, 100000), 0);
    });

    test('costo 0 → 100% de ganancia (todo el precio es ganancia)', () {
      expect(gananciaBpDesdeCostoYPrecio(0, 100000), 10000);
    });

    test('lanza error si el precio es 0: no hay ganancia infinita silenciosa', () {
      expect(() => gananciaBpDesdeCostoYPrecio(1000, 0), throwsArgumentError);
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

  group('precioConGananciaACentena — porcentaje del proveedor, redondeo a la próxima centena', () {
    test('costo \$700 con 30% cae justo en centena: \$1.000, no sube', () {
      expect(precioConGananciaACentena(70000, 3000), 100000);
    });

    test('costo \$1.000 con 30% = \$1.428,57 sube a \$1.500', () {
      expect(precioConGananciaACentena(100000, 3000), 150000);
    });

    test('un peso por encima de una centena sube a la siguiente', () {
      // 100.01 pesos de costo con 0% = \$100,01 → \$200.
      expect(precioConGananciaACentena(10001, 0), 20000);
      expect(precioConGananciaACentena(10000, 0), 10000);
    });

    test('con 50% duplica y redondea (\$1.250 → \$2.500)', () {
      expect(precioConGananciaACentena(125000, 5000), 250000);
    });

    test('un costo chico siempre da al menos \$100 (nunca \$0)', () {
      expect(precioConGananciaACentena(500, 3000), 10000);
    });

    test('no usa doubles: cuenta exacta con enteros', () {
      expect(precioConGananciaACentena(29000, 3000), 50000); // \$290 / 0,7 = \$414,29 → \$500
    });

    test('lanza error con 100% o más de ganancia', () {
      expect(() => precioConGananciaACentena(100000, 10000), throwsArgumentError);
    });
  });

  group('precioDePromo — costo + ganancia, nunca más que el precio de lista', () {
    test('cuando el porcentaje no llega a la lista, gana el porcentaje', () {
      // Costos 1.000 + 500 = 1.500; con 30% = 2.142,86 → 2.200; lista 1.400 + 900 = 2.300.
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 230000, gananciaBp: 3000);
      expect(r.precioCentavos, 220000);
      expect(r.topeadoPorLista, false);
    });

    test('si el porcentaje pasa la lista, queda en la lista (tope)', () {
      // 1.500 con 30% = 2.142,86 → 2.200, pero la lista suma 2.100: tope.
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 210000, gananciaBp: 3000);
      expect(r.precioCentavos, 210000);
      expect(r.topeadoPorLista, true);
    });

    test('el tope va después del redondeo: 2.142,86 no se redondea a 2.200 si la lista es 2.150', () {
      final r = precioDePromo(costoTotalCentavos: 150000, precioListaTotalCentavos: 215000, gananciaBp: 3000);
      expect(r.precioCentavos, 215000);
      expect(r.topeadoPorLista, true);
    });

    test('igual a la lista no es tope', () {
      final r = precioDePromo(costoTotalCentavos: 70000, precioListaTotalCentavos: 100000, gananciaBp: 3000);
      expect(r.precioCentavos, 100000);
      expect(r.topeadoPorLista, false);
    });
  });
}
