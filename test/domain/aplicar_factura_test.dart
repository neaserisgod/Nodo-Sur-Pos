import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/aplicar_factura.dart';

/// Aplicar una factura revisada (El dueño, 2026-10-07).
void main() {
  group('qué frena aplicar', () {
    test('todo vinculado o marcado "No va", con proveedor: se puede', () {
      expect(
        motivosParaNoAplicar(proveedorId: 1, tipo: 'A', lineas: const [
          LineaParaAplicar(productoId: 5, unidades: 4, totalCentavos: 1000),
          LineaParaAplicar(productoId: null, unidades: 1, totalCentavos: 500, noVa: true),
        ]),
        isEmpty,
      );
    });

    test('sin proveedor, una línea sin producto ni "No va", o una nota de crédito: no', () {
      final motivos = motivosParaNoAplicar(proveedorId: null, tipo: 'NC', lineas: const [
        LineaParaAplicar(productoId: 5, unidades: 4, totalCentavos: 1000),
        LineaParaAplicar(productoId: null, unidades: 1, totalCentavos: 500),
      ]);
      expect(motivos, hasLength(3));
      expect(motivos.last, contains('Línea 2'));
    });

    test('reconoce las notas de crédito como las escriba la IA', () {
      for (final t in ['NC', 'nc-a', 'Nota de Crédito', 'NOTA DE CREDITO B']) {
        expect(esNotaDeCredito(t), isTrue, reason: t);
      }
      for (final t in ['A', 'B', 'remito', null]) {
        expect(esNotaDeCredito(t), isFalse, reason: '$t');
      }
    });
  });

  test('el número de factura se compara sin ceros ni guiones distintos', () {
    expect(numeroDeFacturaNormalizado('0011-00266439'), '11-266439');
    expect(numeroDeFacturaNormalizado('11 - 266439'), '11-266439');
    expect(numeroDeFacturaNormalizado('A 0011-00266439'), '11-266439');
    expect(numeroDeFacturaNormalizado(''), isNull);
    expect(numeroDeFacturaNormalizado(null), isNull);
  });

  group('lo que se aplica a cada producto', () {
    test('"No va" y sin producto no tocan stock ni costo; el costo por unidad se redondea hacia arriba al peso', () {
      final a = aplicacionesPorProducto(const [
        LineaParaAplicar(productoId: 5, unidades: 4, totalCentavos: 877421),
        LineaParaAplicar(productoId: 6, unidades: 2, totalCentavos: 1000, noVa: true),
        LineaParaAplicar(productoId: null, unidades: 1, totalCentavos: 500, noVa: true),
      ]);
      expect(a, hasLength(1));
      expect(a.single.productoId, 5);
      expect(a.single.unidades, 4);
      expect(a.single.costoUnitarioCentavos, 219400); // 8.774,21 / 4 = 2.193,55 → $2.194
    });

    test('el mismo producto en dos líneas suma las unidades y promedia lo que se pagó', () {
      final a = aplicacionesPorProducto(const [
        LineaParaAplicar(productoId: 5, unidades: 10, totalCentavos: 100000),
        LineaParaAplicar(productoId: 5, unidades: 10, totalCentavos: 120000),
      ]);
      expect(a.single.unidades, 20);
      expect(a.single.costoUnitarioCentavos, 11000);
    });
  });

  test('la deuda es el total impreso; sin total, la suma de las líneas (con las "No va" adentro)', () {
    const lineas = [
      LineaParaAplicar(productoId: 5, unidades: 1, totalCentavos: 1000),
      LineaParaAplicar(productoId: null, unidades: 1, totalCentavos: 500, noVa: true),
    ];
    expect(montoDeLaDeuda(totalImpresoCentavos: 1600, lineas: lineas), 1600);
    expect(montoDeLaDeuda(totalImpresoCentavos: null, lineas: lineas), 1500);
  });
}
