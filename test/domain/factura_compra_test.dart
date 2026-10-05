import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/factura_compra.dart';

/// Cuentas de las facturas de compra, con facturas REALES del dueño (2026-10-05) como casos: cada una trae el IVA, los descuentos y
/// los impuestos de una manera distinta, y todas tienen que cerrar con el total impreso.
void main() {
  // Plata en centavos: $1.234,56 → 123456.
  int c(double pesos) => (pesos * 100).round();

  LineaDeFactura linea(double neto, int unidades, {int alicuotaBp = 2100, double internos = 0}) =>
      LineaDeFactura(unidades: unidades, netoCentavos: c(neto), alicuotaBp: alicuotaBp, internosCentavos: c(internos));

  group('Elpar (neto con descuento por línea, IIBB e IVA al pie)', () {
    // Los netos ya traen el 5 % por línea aplicado (el subtotal impreso es el de después del descuento).
    final lineas = [
      linea(4885.04, 3),
      linea(3044.63, 3),
      linea(3864.41, 2),
      linea(3089.22, 2),
      linea(7251.41, 4),
      linea(2017.77, 2),
      linea(2710.25, 2),
      linea(2017.77, 2),
      linea(3614.71, 2),
      linea(3614.71, 2),
    ];
    final factura = FacturaDeCompra(lineas: lineas, percepcionesCentavos: c(361.10));

    test('cierra con el total impreso: 36.109,92 + IIBB 361,10 + IVA 7.583,08 = 44.054,10', () {
      final control = controlarFactura(factura, totalImpresoCentavos: c(44054.10));
      expect(control.cierra, isTrue);
      expect(control.diferenciaCentavos.abs(), lessThanOrEqualTo(1)); // un centavo de redondeo del IVA
    });

    test('el costo por unidad lleva IVA y la percepción repartida', () {
      final costos = costosDeFactura(factura);
      // Yogur de frutilla: 2 unidades, neto 2.017,77 → +IVA 423,73 +IIBB 20,17 = 2.461,67 → 1.230,84 → $1.231 (techo al peso).
      expect(costos[5].costoUnitarioCentavos, 123100);
      expect(costos[5].ivaCentavos, 42373);
      expect(costos[5].percepcionesCentavos, 2017);
    });

    test('sin repartir la percepción, el costo baja', () {
      final costos = costosDeFactura(factura, percepcionesAlCosto: false);
      expect(costos[5].costoUnitarioCentavos, 122100);
      expect(costos[5].percepcionesCentavos, 0);
    });

    test('lo repartido de la percepción suma exactamente lo impreso', () {
      final costos = costosDeFactura(factura);
      expect(costos.fold<int>(0, (a, x) => a + x.percepcionesCentavos), c(361.10));
    });
  });

  group('Puelche (línea de descuento global en negativo; el % por producto es informativo)', () {
    // 4 productos: el 10 % del último ya está en su precio (informativo), por eso NO se vuelve a aplicar.
    final puelche1 = FacturaDeCompra(
      lineas: [linea(33212.83, 18), linea(13552.80, 12), linea(13552.80, 12), linea(9963.84, 6)],
      descuentoGlobalCentavos: c(3514.12),
    );

    test('cierra al centavo: 70.282,27 − 3.514,12 = 66.768,15; + IVA 14.021,31 = 80.789,46', () {
      final control = controlarFactura(puelche1, totalImpresoCentavos: c(80789.46));
      expect(control.cierra, isTrue);
      expect(control.diferenciaCentavos, 0);
      expect(control.subtotalCalculadoCentavos, c(66768.15));
    });

    test('el descuento global se reparte entre los productos y baja cada costo', () {
      final costos = costosDeFactura(puelche1);
      // La bebida de 18 unidades: neto 33.212,83 − su parte del descuento = 31.552,18; con IVA 38.178,14 → 2.121,01 → $2.122.
      expect(costos[0].netoCentavos, 3155218);
      expect(costos.map((x) => x.costoUnitarioCentavos), [212200, 129900, 129900, 190900]);
    });

    test('lo repartido del descuento suma exactamente lo impreso (sin perder un centavo)', () {
      final costos = costosDeFactura(puelche1);
      final originales = [33212.83, 13552.80, 13552.80, 9963.84].map(c).toList();
      var repartido = 0;
      for (var i = 0; i < costos.length; i++) {
        repartido += originales[i] - costos[i].netoCentavos;
      }
      expect(repartido, c(3514.12));
    });

    test('otra factura de Puelche cierra con un par de centavos de diferencia (redondeo del proveedor)', () {
      final puelche2 = FacturaDeCompra(
        lineas: [
          linea(2670.38, 5),
          linea(3294.12, 2),
          linea(3294.02, 2),
          linea(7914.27, 5),
          linea(5729.11, 1),
          linea(5729.11, 1),
          linea(4266.53, 4),
        ],
        descuentoGlobalCentavos: c(1644.87),
      );
      final control = controlarFactura(puelche2, totalImpresoCentavos: c(37815.72));
      expect(control.cierra, isTrue);
      expect(control.diferenciaCentavos.abs(), lessThanOrEqualTo(control.toleranciaCentavos));
    });
  });

  group('Serra (el importe de la línea trae IVA e impuestos internos adentro)', () {
    // Normalizada: neto = importe − IVA − internos. Solo el tabaco tiene impuestos internos.
    final serra = FacturaDeCompra(
      lineas: [
        linea(5206.01, 2), // Bagley surtido, ya con su 5 % de bonificación
        linea(4789.98, 3),
        for (var i = 0; i < 6; i++) linea(3646.33, 3), // alfajores
        linea(8592.98, 12),
        linea(8592.98, 12),
        linea(33074.30, 10, internos: 7874.80), // tabaco, resaltado a mano
      ],
    );

    test('cierra con el total impreso de 107.257,25 aunque cada línea redondee distinto', () {
      final control = controlarFactura(serra, totalImpresoCentavos: c(107257.25));
      expect(control.cierra, isTrue);
      expect(control.diferenciaCentavos.abs(), lessThanOrEqualTo(3));
    });

    test('el costo del tabaco incluye el IVA y los impuestos internos', () {
      final costos = costosDeFactura(serra);
      // 33.074,30 + IVA 6.945,60 + internos 7.874,80 = 47.894,70 → 4.789,47 por unidad → $4.790.
      expect(costos.last.totalCentavos, 4789470);
      expect(costos.last.costoUnitarioCentavos, 479000);
    });

    test('el costo de un producto con bonificación sale de su neto ya bonificado', () {
      final costos = costosDeFactura(serra);
      expect(costos.first.costoUnitarioCentavos, 315000); // 6.299,27 / 2 = 3.149,64 → $3.150
    });
  });

  group('controlarFactura: atrapa lo que está mal leído', () {
    final base = FacturaDeCompra(
      lineas: [linea(33212.83, 18), linea(13552.80, 12), linea(13552.80, 12), linea(9963.84, 6)],
      descuentoGlobalCentavos: c(3514.12),
    );

    test('un dígito mal leído (100 pesos de más en una línea) no cierra', () {
      final mal = FacturaDeCompra(
        lineas: [linea(33312.83, 18), ...base.lineas.skip(1)],
        descuentoGlobalCentavos: base.descuentoGlobalCentavos,
      );
      final control = controlarFactura(mal, totalImpresoCentavos: c(80789.46));
      expect(control.cierra, isFalse);
      expect(control.diferenciaCentavos, greaterThan(10000));
    });

    test('aplicar dos veces el descuento "informativo" tampoco cierra', () {
      // El 10 % del cuarto producto ya está en su precio: si se descontara otra vez, el total no coincide.
      final dobleDescuento = FacturaDeCompra(
        lineas: [...base.lineas.take(3), linea(9963.84 * 0.9, 6)],
        descuentoGlobalCentavos: base.descuentoGlobalCentavos,
      );
      expect(controlarFactura(dobleDescuento, totalImpresoCentavos: c(80789.46)).cierra, isFalse);
    });

    test('la tolerancia crece un poco con la cantidad de líneas pero nunca tapa un error de pesos', () {
      expect(controlarFactura(base, totalImpresoCentavos: c(80789.46)).toleranciaCentavos, lessThan(100));
    });
  });

  group('impuestos internos al pie (Bebidas del Lago)', () {
    test('se reparten entre las líneas según su valor y entran al costo', () {
      final f = FacturaDeCompra(
        lineas: [linea(100, 1, alicuotaBp: 0), linea(300, 1, alicuotaBp: 0)],
        internosAlPieCentavos: c(4),
      );
      final costos = costosDeFactura(f);
      expect(costos[0].internosCentavos, 100);
      expect(costos[1].internosCentavos, 300);
      expect(costos[0].totalCentavos, 10100);
      expect(costos[1].totalCentavos, 30300);
    });
  });

  group('netoDesdeImporteConIva (facturas con "IVA contenido")', () {
    test('saca el IVA de un importe que ya lo incluye', () {
      expect(netoDesdeImporteConIva(12100, 2100), 10000);
      expect(netoDesdeImporteConIva(11050, 1050), 10000);
      expect(netoDesdeImporteConIva(5000, 0), 5000);
    });

    test('redondea al centavo más cercano', () {
      expect(netoDesdeImporteConIva(10000, 2100), 8264); // 82,6446…
    });
  });

  group('datos inválidos', () {
    test('una línea sin unidades no se puede costear', () {
      expect(() => costosDeFactura(FacturaDeCompra(lineas: [linea(100, 0)])), throwsArgumentError);
    });

    test('un descuento global mayor que la factura entera es un error de lectura', () {
      expect(
        () => costosDeFactura(FacturaDeCompra(lineas: [linea(100, 1)], descuentoGlobalCentavos: c(101))),
        throwsArgumentError,
      );
    });

    test('una factura sin líneas no tiene costos', () {
      expect(costosDeFactura(const FacturaDeCompra(lineas: [])), isEmpty);
    });
  });
}
