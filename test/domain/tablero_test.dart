import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/tablero.dart';

void main() {
  group('ventasPorHora', () {
    test('suma por hora del día y solo trae las horas con venta', () {
      final r = ventasPorHora([
        (fecha: DateTime(2026, 9, 26, 9, 5), totalCentavos: 100000),
        (fecha: DateTime(2026, 9, 26, 9, 59), totalCentavos: 50000),
        (fecha: DateTime(2026, 9, 26, 21, 0), totalCentavos: 250000),
      ]);
      expect(r, {9: 150000, 21: 250000});
    });

    test('sin ventas, vacío', () => expect(ventasPorHora(const []), isEmpty));
  });

  group('masVendidos', () {
    test('agrupa por producto y ordena por plata vendida, no por unidades', () {
      final r = masVendidos([
        (clave: 'coca', nombre: 'Coca 500', esPesable: false, cantidad: 3, gramos: 0, subtotalCentavos: 336000),
        (clave: 'queso', nombre: 'Queso', esPesable: true, cantidad: 0, gramos: 300, subtotalCentavos: 255000),
        (clave: 'coca', nombre: 'Coca 500', esPesable: false, cantidad: 1, gramos: 0, subtotalCentavos: 112000),
        (clave: 'queso', nombre: 'Queso', esPesable: true, cantidad: 0, gramos: 250, subtotalCentavos: 212500),
        (clave: 'chicle', nombre: 'Chicle', esPesable: false, cantidad: 20, gramos: 0, subtotalCentavos: 20000),
      ]);
      expect(r.map((p) => p.nombre), ['Queso', 'Coca 500', 'Chicle']);
      expect(r.first.gramos, 550);
      expect(r[1].cantidad, 4);
      expect(r[1].vendidoCentavos, 448000);
    });

    test('respeta el límite', () {
      final lineas = [
        for (var i = 0; i < 8; i++)
          (clave: '$i', nombre: 'P$i', esPesable: false, cantidad: 1, gramos: 0, subtotalCentavos: 1000 * (i + 1)),
      ];
      expect(masVendidos(lineas, limite: 5).length, 5);
    });
  });

  group('avisaPorStock', () {
    test('por debajo del mínimo avisa', () {
      expect(avisaPorStock(stock: 3, minimo: 5, vendidoHacePoco: false), isTrue);
    });

    test('en el mínimo justo no avisa', () {
      expect(avisaPorStock(stock: 5, minimo: 5, vendidoHacePoco: true), isFalse);
    });

    test('agotado y vendido hace poco avisa aunque no tenga mínimo (desaparece de Venta)', () {
      expect(avisaPorStock(stock: 0, minimo: null, vendidoHacePoco: true), isTrue);
      expect(avisaPorStock(stock: -3, minimo: 0, vendidoHacePoco: true), isTrue);
    });

    test('agotado pero sin ventas recientes no avisa (producto que ya no se trabaja)', () {
      expect(avisaPorStock(stock: 0, minimo: null, vendidoHacePoco: false), isFalse);
    });
  });
}
