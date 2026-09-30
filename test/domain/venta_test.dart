import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

void main() {
  const configRecargo = ConfigRecargoCigarrillos(
    primerAtadoCentavos: 30000,
    atadoAdicionalCentavos: 10000,
  );
  const pasoRedondeo = 10000;

  group('LineaVentaPorUnidad', () {
    test('subtotal = precio unitario × cantidad', () {
      const linea = LineaVentaPorUnidad(
        productoId: 'p1',
        nombreProducto: 'Coca-Cola 500ml',
        proveedorId: 'C',
        cantidad: 3,
        precioUnitarioCentavos: 112000,
        costoUnitarioCentavos: 80000,
      );
      expect(linea.subtotalCentavos, 336000);
      expect(linea.costoLineaCentavos, 240000);
    });

    test(
      'sin costo cargado (alta rápida o "Varios"): costoLineaCentavos es null, no 0',
      () {
        const linea = LineaVentaPorUnidad(
          productoId: 'p2',
          nombreProducto: 'Producto nuevo escaneado',
          proveedorId: null,
          cantidad: 1,
          precioUnitarioCentavos: 50000,
        );
        expect(linea.costoUnitarioCentavos, isNull);
        expect(linea.costoLineaCentavos, isNull);
        expect(
          linea.subtotalCentavos,
          50000,
        ); // el precio sí se puede cobrar igual
      },
    );
  });

  group('LineaVentaPesable', () {
    test(
      'subtotal y costo usan el mismo helper de gramos que el módulo pesables',
      () {
        const linea = LineaVentaPesable(
          productoId: 'p3',
          nombreProducto: 'Jamón crudo',
          proveedorId: 'F',
          gramos: 350,
          precioPorKiloCentavos: 300000,
          costoPorKiloCentavos: 180000,
        );
        expect(linea.subtotalCentavos, 105000); // 300000*350/1000
        expect(linea.costoLineaCentavos, 63000); // 180000*350/1000
      },
    );

    test(
      'nunca es Varios ni cigarrillo: un fiambre no puede confundirse con esas categorías',
      () {
        const linea = LineaVentaPesable(
          productoId: 'p3',
          nombreProducto: 'Jamón crudo',
          proveedorId: 'F',
          gramos: 100,
          precioPorKiloCentavos: 300000,
        );
        expect(linea.esVarios, false);
        expect(linea.tipoCigarrillo, TipoCigarrillo.ninguno);
      },
    );
  });

  group('Venta — agregados sobre las líneas', () {
    test(
      'subtotalCentavos suma todas las líneas, unidad y pesable mezcladas',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'p1',
              nombreProducto: 'Coca-Cola',
              proveedorId: 'C',
              cantidad: 2,
              precioUnitarioCentavos: 112000,
            ),
            LineaVentaPesable(
              productoId: 'p3',
              nombreProducto: 'Jamón crudo',
              proveedorId: 'F',
              gramos: 350,
              precioPorKiloCentavos: 300000,
            ),
          ],
        );
        // 112000*2 + (300000*350/1000) = 224000 + 105000 = 329000
        expect(venta.subtotalCentavos, 329000);
      },
    );

    test(
      '"Varios" suma al subtotal igual que cualquier línea, aunque no tenga costo',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'varios',
              nombreProducto: 'Varios',
              proveedorId: null,
              cantidad: 1,
              esVarios: true,
              precioUnitarioCentavos: 50000,
            ),
          ],
        );
        expect(venta.subtotalCentavos, 50000);
      },
    );

    test(
      'cuenta atados y sueltos por separado, ignorando las líneas que no son cigarrillos',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'cig-atado',
              nombreProducto: 'Marlboro atado',
              proveedorId: 'S',
              cantidad: 3,
              tipoCigarrillo: TipoCigarrillo.atado,
              precioUnitarioCentavos: 500000,
            ),
            LineaVentaPorUnidad(
              productoId: 'cig-suelto',
              nombreProducto: 'Marlboro suelto',
              proveedorId: 'S',
              cantidad: 5,
              tipoCigarrillo: TipoCigarrillo.suelto,
              precioUnitarioCentavos: 50000,
            ),
            LineaVentaPorUnidad(
              productoId: 'coca',
              nombreProducto: 'Coca-Cola',
              proveedorId: 'C',
              cantidad: 10, // no debe contaminar el conteo de cigarrillos
              precioUnitarioCentavos: 112000,
            ),
          ],
        );
        expect(venta.cantidadAtadosCigarrillos, 3);
        expect(venta.cantidadSueltosCigarrillos, 5);
      },
    );

    test('una venta sin cigarrillos tiene atados y sueltos en 0', () {
      const venta = Venta(
        lineas: [
          LineaVentaPorUnidad(
            productoId: 'coca',
            nombreProducto: 'Coca-Cola',
            proveedorId: 'C',
            cantidad: 1,
            precioUnitarioCentavos: 112000,
          ),
        ],
      );
      expect(venta.cantidadAtadosCigarrillos, 0);
      expect(venta.cantidadSueltosCigarrillos, 0);
    });
  });

  group(
    'calcularTotalVenta — compone recargo y redondeo en el orden fijo de la Regla 6',
    () {
      const ventaSoloAlmacen = Venta(
        lineas: [
          LineaVentaPorUnidad(
            productoId: 'coca',
            nombreProducto: 'Coca-Cola',
            proveedorId: 'C',
            cantidad: 1,
            precioUnitarioCentavos: 5400,
          ),
        ],
      );

      test('sin cigarrillos, efectivo: solo actúa el redondeo', () {
        final r = calcularTotalVenta(
          venta: ventaSoloAlmacen,
          composicionPago: ComposicionPago.efectivo,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
        );
        expect(r.subtotalCentavos, 5400);
        expect(r.recargoCigarrillosCentavos, 0);
        expect(r.redondeoCentavos, 4600);
        expect(r.totalCentavos, 10000);
      });

      test('sin cigarrillos, virtual: ni recargo ni redondeo', () {
        final r = calcularTotalVenta(
          venta: ventaSoloAlmacen,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
        );
        expect(r.recargoCigarrillosCentavos, 0);
        expect(r.redondeoCentavos, 0);
        expect(r.totalCentavos, 5400);
      });

      test('con 1 atado, virtual: aparece el recargo y no hay redondeo', () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'cig',
              nombreProducto: 'Marlboro',
              proveedorId: 'S',
              cantidad: 1,
              tipoCigarrillo: TipoCigarrillo.atado,
              precioUnitarioCentavos: 500000,
            ),
          ],
        );
        final r = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
        );
        expect(r.subtotalCentavos, 500000);
        expect(r.recargoCigarrillosCentavos, 30000);
        expect(r.redondeoCentavos, 0); // virtual no redondea, con o sin recargo
        expect(r.totalCentavos, 530000);
      });

      test(
        'el redondeo se aplica DESPUÉS de sumar el recargo, no sobre el subtotal solo '
        '(Regla 6: "el split se aplica sobre el total ya con recargo")',
        () {
          const venta = Venta(
            lineas: [
              LineaVentaPorUnidad(
                productoId: 'cig',
                nombreProducto: 'Marlboro',
                proveedorId: 'S',
                cantidad: 1,
                tipoCigarrillo: TipoCigarrillo.atado,
                precioUnitarioCentavos: 9000,
              ),
            ],
          );
          // Config con un recargo que NO es múltiplo del paso, para que el
          // orden de las operaciones cambie el resultado si se invirtiera.
          const configRecargoDesalineado = ConfigRecargoCigarrillos(
            primerAtadoCentavos: 25000,
            atadoAdicionalCentavos: 10000,
          );

          final r = calcularTotalVenta(
            venta: venta,
            composicionPago: ComposicionPago.mixto,
            configRecargoCigarrillos: configRecargoDesalineado,
            pasoRedondeoCentavos: pasoRedondeo,
          );

          // subtotal 9000 + recargo 25000 = 34000 → redondea a 40000 (paso 10000)
          // Si se redondeara el subtotal SOLO (9000→10000) y se sumara el
          // recargo después, el total daría 35000: un valor distinto.
          expect(r.subtotalCentavos, 9000);
          expect(r.recargoCigarrillosCentavos, 25000);
          expect(r.redondeoCentavos, 6000);
          expect(r.totalCentavos, 40000);
        },
      );

      test('con cigarrillos mixto: recargo Y redondeo actúan juntos', () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'cig',
              nombreProducto: 'Marlboro',
              proveedorId: 'S',
              cantidad: 2,
              tipoCigarrillo: TipoCigarrillo.atado,
              precioUnitarioCentavos: 500000,
            ),
          ],
        );
        final r = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.mixto,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
        );
        // subtotal 1000000 + recargo (30000+10000=40000) = 1040000, ya exacto
        expect(r.subtotalCentavos, 1000000);
        expect(r.recargoCigarrillosCentavos, 40000);
        expect(r.redondeoCentavos, 0);
        expect(r.totalCentavos, 1040000);
      });

      test(
        'cigarrillos sueltos con efectivo: sin recargo, el redondeo actúa solo sobre el subtotal',
        () {
          const venta = Venta(
            lineas: [
              LineaVentaPorUnidad(
                productoId: 'cig-suelto',
                nombreProducto: 'Marlboro suelto',
                proveedorId: 'S',
                cantidad: 3,
                tipoCigarrillo: TipoCigarrillo.suelto,
                precioUnitarioCentavos: 50000,
              ),
            ],
          );
          final r = calcularTotalVenta(
            venta: venta,
            composicionPago: ComposicionPago.efectivo,
            configRecargoCigarrillos: configRecargo,
            pasoRedondeoCentavos: pasoRedondeo,
          );
          expect(r.subtotalCentavos, 150000);
          expect(r.recargoCigarrillosCentavos, 0);
          expect(r.redondeoCentavos, 0); // 150000 ya es múltiplo de 10000
          expect(r.totalCentavos, 150000);
        },
      );
    },
  );

  group('calcularTotalVenta — descuento (Regla 17 generalizada)', () {
    const ventaSoloAlmacen = Venta(
      lineas: [
        LineaVentaPorUnidad(
          productoId: 'coca',
          nombreProducto: 'Coca-Cola',
          proveedorId: 'C',
          cantidad: 1,
          precioUnitarioCentavos: 5400,
        ),
      ],
    );

    test(
      'sin tipoDescuento: descuentoCentavos es 0, compatible con todo el código anterior',
      () {
        final r = calcularTotalVenta(
          venta: ventaSoloAlmacen,
          composicionPago: ComposicionPago.efectivo,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
        );
        expect(r.descuentoCentavos, 0);
      },
    );

    test(
      'monto fijo, virtual: se resta del total, sin redondeo de por medio',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'p',
              nombreProducto: 'Producto',
              proveedorId: null,
              cantidad: 1,
              precioUnitarioCentavos: 1000000,
            ),
          ],
        );
        final r = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
          tipoDescuento: TipoDescuento.monto,
          valorDescuento: 200000,
        );
        expect(r.descuentoCentavos, 200000);
        expect(r.totalCentavos, 800000);
      },
    );

    test(
      'Cliente Frecuente: 15% sobre el total real de una compra, virtual (sin redondeo)',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'paleta',
              nombreProducto: 'Paleta',
              proveedorId: 'F',
              cantidad: 1,
              precioUnitarioCentavos: 700000,
            ),
            LineaVentaPesable(
              productoId: 'queso',
              nombreProducto: 'Queso',
              proveedorId: 'F',
              gramos: 500,
              precioPorKiloCentavos: 300000,
            ),
          ],
        );
        final r = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
          tipoDescuento: TipoDescuento.porcentaje,
          valorDescuento: 1500,
        );
        // subtotal: 700000 + subtotalPesable(300000, 500) = 700000 + 150000 = 850000
        expect(r.subtotalCentavos, 850000);
        expect(r.descuentoCentavos, 127500); // 15% de 850000
        expect(r.totalCentavos, 722500);
      },
    );

    test(
      'el descuento se aplica sobre el total CON recargo, antes de redondear (orden fijo)',
      () {
        const venta = Venta(
          lineas: [
            LineaVentaPorUnidad(
              productoId: 'cig',
              nombreProducto: 'Marlboro',
              proveedorId: 'S',
              cantidad: 1,
              tipoCigarrillo: TipoCigarrillo.atado,
              precioUnitarioCentavos: 100000,
            ),
          ],
        );
        final r = calcularTotalVenta(
          venta: venta,
          composicionPago: ComposicionPago.mixto,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
          tipoDescuento: TipoDescuento.monto,
          valorDescuento: 20000,
        );
        // subtotal 100000 + recargo 30000 = 130000; -20000 descuento = 110000;
        // ya es múltiplo de 10000, sin redondeo.
        expect(r.subtotalCentavos, 100000);
        expect(r.recargoCigarrillosCentavos, 30000);
        expect(r.descuentoCentavos, 20000);
        expect(r.redondeoCentavos, 0);
        expect(r.totalCentavos, 110000);
      },
    );

    test(
      'un descuento que dejaría el total redondeado distinto si fuera después del redondeo',
      () {
        final r = calcularTotalVenta(
          venta: ventaSoloAlmacen, // subtotal 5400, efectivo
          composicionPago: ComposicionPago.efectivo,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
          tipoDescuento: TipoDescuento.monto,
          valorDescuento: 400,
        );
        // 5400 - 400 = 5000 → redondea a 10000 (paso 10000).
        // Si el descuento fuera DESPUÉS del redondeo (5400→10000, -400=9600),
        // el total sería 9600: un valor distinto, y ya no un múltiplo del paso.
        expect(r.descuentoCentavos, 400);
        expect(r.totalCentavos, 10000);
      },
    );

    test(
      'un monto de descuento mayor al total nunca deja un total negativo',
      () {
        final r = calcularTotalVenta(
          venta: ventaSoloAlmacen, // subtotal 5400
          composicionPago: ComposicionPago.virtual,
          configRecargoCigarrillos: configRecargo,
          pasoRedondeoCentavos: pasoRedondeo,
          tipoDescuento: TipoDescuento.monto,
          valorDescuento: 999999,
        );
        expect(r.descuentoCentavos, 5400);
        expect(r.totalCentavos, 0);
      },
    );
  });
}
