import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/stock_valorizado.dart';

void main() {
  group('calcularStockValorizado', () {
    test('agrupa por proveedor: costo × stock de cada producto', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 10, costoCentavos: 50000),
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 3, costoCentavos: 20000),
        const ProductoParaValorizar(proveedorId: 'A', esPesable: false, stock: 5, costoCentavos: 100000),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], 500000 + 60000);
      expect(resultado.valorizadoPorProveedorCentavos['A'], 500000);
    });

    test('un pesable valoriza con costoPorKiloCentavos × stockGramos / 1000, misma fórmula que subtotalPesable', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(
          proveedorId: 'S',
          esPesable: true,
          stockGramos: 3200,
          costoPorKiloCentavos: 850000,
        ),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], 2720000);
    });

    test('producto sin costo cargado no se cuenta como \$0 — se reporta aparte, por proveedor', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 10, costoCentavos: 50000),
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 5, costoCentavos: null),
        const ProductoParaValorizar(proveedorId: 'A', esPesable: false, stock: 2, costoCentavos: null),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], 500000); // solo el que sí tiene costo
      expect(resultado.sinCostoPorProveedor['S'], 1);
      expect(resultado.sinCostoPorProveedor['A'], 1);
      expect(resultado.valorizadoPorProveedorCentavos.containsKey('A'), isFalse);
    });

    test('un pesable sin costo por kilo cargado también se reporta aparte, no como \$0', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: true, stockGramos: 1000, costoPorKiloCentavos: null),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos.containsKey('S'), isFalse);
      expect(resultado.sinCostoPorProveedor['S'], 1);
    });

    test('producto sin proveedor asignado se ignora, no se le puede atribuir a nadie', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: null, esPesable: false, stock: 10, costoCentavos: 50000),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos, isEmpty);
      expect(resultado.sinCostoPorProveedor, isEmpty);
    });

    test('stock negativo valoriza en negativo (Regla 8: el stock informa, nunca bloquea)', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: -3, costoCentavos: 50000),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], -150000);
    });

    test('lista vacía da resultados vacíos, no un error', () {
      final resultado = calcularStockValorizado(productos: const []);

      expect(resultado.valorizadoPorProveedorCentavos, isEmpty);
      expect(resultado.sinCostoPorProveedor, isEmpty);
    });
  });

  group('calcularStockValorizado — a precio de venta (corrección post-revisión)', () {
    test('agrupa por proveedor: precio × stock, en paralelo al costo', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(
          proveedorId: 'S',
          esPesable: false,
          stock: 10,
          costoCentavos: 50000,
          precioCentavos: 80000,
        ),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], 500000);
      expect(resultado.valorizadoAPrecioPorProveedorCentavos['S'], 800000);
    });

    test('un pesable valoriza a precio con precioPorKiloCentavos × stockGramos / 1000', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(
          proveedorId: 'S',
          esPesable: true,
          stockGramos: 3200,
          precioPorKiloCentavos: 950000,
        ),
      ]);

      expect(resultado.valorizadoAPrecioPorProveedorCentavos['S'], 3040000);
    });

    test('sin precio cargado no cuenta como \$0 — se reporta aparte, igual que sin costo', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 10, precioCentavos: null),
      ]);

      expect(resultado.valorizadoAPrecioPorProveedorCentavos.containsKey('S'), isFalse);
      expect(resultado.sinPrecioPorProveedor['S'], 1);
    });

    test('costo y precio se reportan sin faltar por separado: uno puede faltar sin el otro', () {
      final resultado = calcularStockValorizado(productos: [
        const ProductoParaValorizar(proveedorId: 'S', esPesable: false, stock: 10, costoCentavos: 50000, precioCentavos: null),
      ]);

      expect(resultado.valorizadoPorProveedorCentavos['S'], 500000);
      expect(resultado.sinCostoPorProveedor.containsKey('S'), isFalse);
      expect(resultado.valorizadoAPrecioPorProveedorCentavos.containsKey('S'), isFalse);
      expect(resultado.sinPrecioPorProveedor['S'], 1);
    });
  });
}
