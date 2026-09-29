import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/reposicion.dart';

void main() {
  group('calcularReposicion — Regla 5', () {
    test('suma el costo real vendido, agrupado por proveedor', () {
      final r = calcularReposicion(
        lineas: const [
          LineaParaReposicion(
            proveedorId: 'F',
            costoLineaCentavos: 10000,
            precioLineaCentavos: 18000,
          ),
          LineaParaReposicion(
            proveedorId: 'F',
            costoLineaCentavos: 5000,
            precioLineaCentavos: 9000,
          ),
          LineaParaReposicion(
            proveedorId: 'C',
            costoLineaCentavos: 7000,
            precioLineaCentavos: 12000,
          ),
        ],
      );

      expect(r.costoRealPorProveedorCentavos['F'], 15000);
      expect(r.costoRealPorProveedorCentavos['C'], 7000);
      expect(
        r.vendidoPorProveedorCentavos['F'],
        27000,
      ); // 18000 + 9000: precio, no costo
      expect(r.vendidoPorProveedorCentavos['C'], 12000);
    });

    test(
      'vendidoPorProveedorCentavos es precio, no costo — y cuenta aunque falte el costo (Regla 9)',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: 'C',
              costoLineaCentavos: null, // alta rápida sin completar
              precioLineaCentavos: 8000,
            ),
          ],
        );

        expect(
          r.vendidoPorProveedorCentavos['C'],
          8000,
        ); // el precio cobrado no falta nunca
        expect(
          r.costoRealPorProveedorCentavos.containsKey('C'),
          false,
        ); // el costo real sí falta
      },
    );

    test(
      'vendidoPorProveedorCentavos no cuenta cigarrillos (Regla 6, misma razón que el costo)',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: 'S',
              esCigarrillo: true,
              costoLineaCentavos: 999999,
              precioLineaCentavos: 999999,
            ),
            LineaParaReposicion(
              proveedorId: 'S',
              costoLineaCentavos: 8000,
              precioLineaCentavos: 14000,
            ),
          ],
        );

        expect(r.vendidoPorProveedorCentavos['S'], 14000);
      },
    );

    test(
      '"Varios" (costo null) no genera reposición, pero se reporta lo vendido aparte',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: null,
              costoLineaCentavos: null,
              precioLineaCentavos: 5000,
            ),
            LineaParaReposicion(
              proveedorId: 'F',
              costoLineaCentavos: 15000,
              precioLineaCentavos: 27000,
            ),
          ],
        );

        expect(r.vendidoSinCostoCentavos, 5000);
        expect(r.costoRealPorProveedorCentavos['F'], 15000);
      },
    );

    test(
      'un producto de alta rápida sin costo completado (Regla 9) se trata igual que '
      '"Varios": misma situación, mismo indicador',
      () {
        final r = calcularReposicion(
          lineas: const [
            // Escaneado hoy, todavía sin costo — no es "Varios", es un
            // producto real con proveedor, pero el costo no está cargado.
            LineaParaReposicion(
              proveedorId: 'C',
              costoLineaCentavos: null,
              precioLineaCentavos: 8000,
            ),
          ],
        );

        expect(r.vendidoSinCostoCentavos, 8000);
        expect(r.costoRealPorProveedorCentavos.containsKey('C'), false);
      },
    );

    test('"Varios" y alta rápida sin costo se suman en el mismo indicador', () {
      final r = calcularReposicion(
        lineas: const [
          LineaParaReposicion(
            proveedorId: null,
            costoLineaCentavos: null,
            precioLineaCentavos: 5000,
          ),
          LineaParaReposicion(
            proveedorId: 'C',
            costoLineaCentavos: null,
            precioLineaCentavos: 8000,
          ),
        ],
      );

      expect(r.vendidoSinCostoCentavos, 13000);
    });

    test('los cigarrillos no entran en reposicion: la lata ya es su propia '
        'reposición (Regla 6) y sumarla acá la contaría dos veces', () {
      final r = calcularReposicion(
        lineas: const [
          // Serra vende almacén y cigarrillos con el mismo código de proveedor.
          LineaParaReposicion(
            proveedorId: 'S',
            esCigarrillo: true,
            costoLineaCentavos: 999999,
            precioLineaCentavos: 999999,
          ),
          LineaParaReposicion(
            proveedorId: 'S',
            costoLineaCentavos: 8000,
            precioLineaCentavos: 14000,
          ),
        ],
      );

      expect(r.costoRealPorProveedorCentavos['S'], 8000);
    });

    test(
      'línea sin proveedor asignado (con costo, y que no es Varios): se ignora',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: null,
              costoLineaCentavos: 3000,
              precioLineaCentavos: 5000,
            ),
          ],
        );

        expect(r.costoRealPorProveedorCentavos, isEmpty);
        expect(r.vendidoSinCostoCentavos, 0);
      },
    );

    test('lista vacía → todo en cero', () {
      final r = calcularReposicion(lineas: const []);

      expect(r.costoRealPorProveedorCentavos, isEmpty);
      expect(r.gananciaPorProveedorCentavos, isEmpty);
      expect(r.vendidoSinCostoCentavos, 0);
    });
  });

  group('calcularReposicion — ganancia por proveedor (Regla 13)', () {
    test('ganancia = vendido − costo, agrupada por proveedor', () {
      final r = calcularReposicion(
        lineas: const [
          LineaParaReposicion(
            proveedorId: 'F',
            costoLineaCentavos: 10000,
            precioLineaCentavos: 18000,
          ),
          LineaParaReposicion(
            proveedorId: 'F',
            costoLineaCentavos: 5000,
            precioLineaCentavos: 9000,
          ),
          LineaParaReposicion(
            proveedorId: 'C',
            costoLineaCentavos: 7000,
            precioLineaCentavos: 12000,
          ),
        ],
      );

      expect(
        r.gananciaPorProveedorCentavos['F'],
        12000,
      ); // (18000-10000)+(9000-5000)
      expect(r.gananciaPorProveedorCentavos['C'], 5000);
    });

    test(
      'sin costo cargado, no aporta ganancia (no se inventa un costo 0)',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: 'C',
              costoLineaCentavos: null,
              precioLineaCentavos: 8000,
            ),
          ],
        );

        expect(r.gananciaPorProveedorCentavos.containsKey('C'), false);
      },
    );

    test(
      'cigarrillos no aportan ganancia acá — es la de la lata (Regla 6)',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: 'S',
              esCigarrillo: true,
              costoLineaCentavos: 450000,
              precioLineaCentavos: 500000,
            ),
          ],
        );

        expect(r.gananciaPorProveedorCentavos.containsKey('S'), false);
      },
    );

    test(
      'un proveedor puede dar ganancia negativa (se vendió por debajo del costo actual)',
      () {
        final r = calcularReposicion(
          lineas: const [
            LineaParaReposicion(
              proveedorId: 'F',
              costoLineaCentavos: 10000,
              precioLineaCentavos: 8000,
            ),
          ],
        );

        expect(r.gananciaPorProveedorCentavos['F'], -2000);
      },
    );
  });

  group('pendienteBaseTrasPago — separación de fondos', () {
    test('pago exacto: no queda diferencia', () {
      expect(
        pendienteBaseTrasPago(
          separadoCentavos: 18500,
          montoPagadoCentavos: 18500,
        ),
        0,
      );
    });

    test('pago de menos: la diferencia vuelve a pendiente, no se pierde', () {
      expect(
        pendienteBaseTrasPago(
          separadoCentavos: 18500,
          montoPagadoCentavos: 15000,
        ),
        3500,
      );
    });

    test('nada separado y nada pagado: sin diferencia', () {
      expect(
        pendienteBaseTrasPago(separadoCentavos: 0, montoPagadoCentavos: 0),
        0,
      );
    });

    test('pago de más: la diferencia no puede quedar negativa', () {
      expect(
        pendienteBaseTrasPago(
          separadoCentavos: 10000,
          montoPagadoCentavos: 12000,
        ),
        0,
      );
    });
  });

  group('prorratearGananciaPorMedio — Regla 13, retiro de ganancia', () {
    test('venta 100% efectivo: toda la ganancia va a efectivo', () {
      final r = prorratearGananciaPorMedio(
        gananciaCentavos: 40000,
        efectivoDeLaVentaCentavos: 100000,
        virtualDeLaVentaCentavos: 0,
      );
      expect(r.efectivoCentavos, 40000);
      expect(r.virtualCentavos, 0);
    });

    test('venta 100% virtual: toda la ganancia va a virtual', () {
      final r = prorratearGananciaPorMedio(
        gananciaCentavos: 40000,
        efectivoDeLaVentaCentavos: 0,
        virtualDeLaVentaCentavos: 100000,
      );
      expect(r.efectivoCentavos, 0);
      expect(r.virtualCentavos, 40000);
    });

    test('venta mixta 50/50: la ganancia se reparte a prorrata', () {
      final r = prorratearGananciaPorMedio(
        gananciaCentavos: 40000,
        efectivoDeLaVentaCentavos: 50000,
        virtualDeLaVentaCentavos: 50000,
      );
      expect(r.efectivoCentavos, 20000);
      expect(r.virtualCentavos, 20000);
    });

    test(
      'mixta con reparto que no cae exacto: el resto queda del lado virtual, sin perder ni un centavo',
      () {
        // 101 * 500 / 1000 = 50.5 -> trunca a 50, virtual se lleva el resto.
        final r = prorratearGananciaPorMedio(
          gananciaCentavos: 101,
          efectivoDeLaVentaCentavos: 500,
          virtualDeLaVentaCentavos: 500,
        );
        expect(r.efectivoCentavos, 50);
        expect(r.virtualCentavos, 51);
        expect(r.efectivoCentavos + r.virtualCentavos, 101);
      },
    );

    test(
      'mixta con más efectivo que virtual: la ganancia sigue la misma proporción',
      () {
        final r = prorratearGananciaPorMedio(
          gananciaCentavos: 90000,
          efectivoDeLaVentaCentavos: 80000,
          virtualDeLaVentaCentavos: 20000,
        );
        expect(r.efectivoCentavos, 72000); // 90000 * 80000/100000
        expect(r.virtualCentavos, 18000);
      },
    );
  });
}
