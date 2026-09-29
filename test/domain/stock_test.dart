import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/stock.dart';

void main() {
  group('DeltaStock — cuánto cambió un movimiento ya persistido', () {
    test('una venta (resta) da un delta negativo', () {
      const m = DeltaStock(anterior: 20, posterior: 18);
      expect(m.delta, -2);
    });

    test('un ajuste que repone (suma) da un delta positivo', () {
      const m = DeltaStock(anterior: 18, posterior: 25);
      expect(m.delta, 7);
    });

    test('sin cambio, delta 0', () {
      const m = DeltaStock(anterior: 10, posterior: 10);
      expect(m.delta, 0);
    });
  });

  group('stockRecalculado — base congelada + suma de deltas del log', () {
    test('sin movimientos nuevos, devuelve la base tal cual', () {
      expect(stockRecalculado(stockBase: 20, movimientos: []), 20);
    });

    test('un solo movimiento se aplica sobre la base', () {
      final resultado = stockRecalculado(
        stockBase: 20,
        movimientos: [const DeltaStock(anterior: 20, posterior: 18)],
      );
      expect(resultado, 18);
    });

    test('varios movimientos se acumulan', () {
      final resultado = stockRecalculado(
        stockBase: 20,
        movimientos: [
          const DeltaStock(anterior: 20, posterior: 18), // venta de 2
          const DeltaStock(anterior: 18, posterior: 15), // venta de 3
          const DeltaStock(anterior: 15, posterior: 20), // ajuste +5
        ],
      );
      expect(resultado, 20); // 20 - 2 - 3 + 5
    });

    test(
      'el orden de los movimientos no importa — sumar deltas es conmutativo, '
      'así que no hace falta un reloj compartido entre dos dispositivos '
      'para que el resultado sea el mismo sin importar en qué orden cada uno '
      'los vio',
      () {
        final movimientos = [
          const DeltaStock(anterior: 20, posterior: 18), // -2
          const DeltaStock(anterior: 18, posterior: 15), // -3
          const DeltaStock(anterior: 15, posterior: 20), // +5
        ];

        final enOrden = stockRecalculado(stockBase: 20, movimientos: movimientos);
        final alReves = stockRecalculado(
          stockBase: 20,
          movimientos: movimientos.reversed.toList(),
        );

        expect(enOrden, alReves);
      },
    );

    test(
      'dos dispositivos venden el mismo producto offline en paralelo — al '
      'sincronizar el log de los dos, las dos ventas se suman en vez de que '
      'una tape a la otra (el problema real que motiva esta función)',
      () {
        // Los dos partieron de la misma base (20) sin saber uno del otro.
        final ventaDelCelular = const DeltaStock(anterior: 20, posterior: 17); // vendió 3
        final ventaDeLaPc = const DeltaStock(anterior: 20, posterior: 18); // vendió 2

        final resultado = stockRecalculado(
          stockBase: 20,
          movimientos: [ventaDelCelular, ventaDeLaPc],
        );

        // Si se sincronizara la columna `stock` directamente en vez del log,
        // el que sincronizara último pisaría al otro (17 o 18) y una de las
        // dos ventas desaparecería del conteo. Sumando deltas, las dos
        // sobreviven: 20 - 3 - 2 = 15.
        expect(resultado, 15);
      },
    );

    test('puede dar negativo — Regla 8: el stock nunca bloquea', () {
      final resultado = stockRecalculado(
        stockBase: 2,
        movimientos: [const DeltaStock(anterior: 2, posterior: -1)],
      );
      expect(resultado, -1);
    });
  });
}
