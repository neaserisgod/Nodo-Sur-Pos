import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/factura_compra.dart';
import 'package:la_plazoleta/domain/lectura_factura.dart';

/// Lo que devuelve la IA, simulado con facturas REALES del dueño (2026-10-05), y cómo se lleva a las cuentas.
void main() {
  Map<String, dynamic> linea(
    String descripcion,
    num? cantidad,
    num? precio,
    num importe, {
    num? descuento,
    num alicuota = 21,
    num? internos,
    bool detalle = false,
  }) => {
        'descripcion': descripcion,
        'cantidad': cantidad,
        'precio_unitario': precio,
        'descuento_pct': descuento,
        'importe': importe,
        'alicuota_iva': alicuota,
        'internos_importe': ?internos,
        if (detalle) 'es_detalle': true,
      };

  Map<String, dynamic> factura(List<Map<String, dynamic>> lineas, Map<String, dynamic> pie, {Map<String, dynamic>? extra}) => {
        'facturas': [
          {
            'proveedor': {'razon_social': 'Proveedor', 'cuit': '30-70817475-7'},
            'tipo': 'A',
            'numero': '0011-00266439',
            'fecha': '2026-07-24',
            'condicion_pago': 'cuenta_corriente',
            'lineas': lineas,
            'pie': pie,
            ...?extra,
          },
        ],
      };

  final elpar = factura(
    [
      linea('SW22204 - SALCHICHAS SWIFT S/GLUTEN 6 U X 225GR (24)', 3, 1714.05, 4885.04, descuento: 5),
      linea('SW23251 - SALCHICHAS LA BLANCA 6 U X 190GR (28)', 3, 1014.88, 3044.63),
      linea('10304461 - LACTAL PAN MESA CHICO X 315G (18)', 2, 2033.90, 3864.41, descuento: 5),
      linea('10305295 - LACTAL PAN DE PANCHO X 6 U (16)', 2, 1625.90, 3089.22, descuento: 5),
      linea('1042 - CREMA SIMPLE X 200 GR (24)', 4, 1908.26, 7251.41, descuento: 5),
      linea('3601 - YOGURT ENTERO VAINILLA X 190 GR (20)', 2, 1061.98, 2017.77, descuento: 5),
      linea('3700 - YOGURT ENTERO TOP MAIZ AZUC. (20)', 2, 1426.45, 2710.25, descuento: 5),
      linea('3600 - YOGURT ENTERO FRUTILLA X 190 GR(20)', 2, 1061.98, 2017.77, descuento: 5),
      linea('4141 - YOGURT VAINILLA SACHET X 900 G (12)', 2, 1902.48, 3614.71, descuento: 5),
      linea('4140 - YOGURT FRUTILLA SACHET X 900 G (12)', 2, 1902.48, 3614.71, descuento: 5),
    ],
    {'subtotal': 36109.92, 'percepciones': 361.10, 'iva_total': 7583.08, 'total': 44054.10},
  );

  Map<String, dynamic> puelche({bool descuentoComoLinea = false, num importePrimera = 33212.83}) => factura(
        [
          linea('Bebida Energizante Energy Drink 473 cc', 18, 1845.157, importePrimera),
          linea('Bebida Energizante Energy Drink 269 ml', 12, 1129.400, 13552.80),
          linea('Bebida Energizante Zero Sugar 269 ml', 12, 1129.400, 13552.80),
          // El 10 % de esta línea es solo informativo: el precio ya lo trae aplicado.
          linea('Bebida Energizante Zero Sugar Energy Drink 473 cc', 6, 1660.640, 9963.84, descuento: 10),
          if (descuentoComoLinea) linea('Descuento 5.00%', null, null, -3514.12),
        ],
        {'subtotal': 66768.15, 'descuento_global': descuentoComoLinea ? 0 : 3514.12, 'iva_total': 14021.31, 'total': 80789.46},
      );

  final serra = factura(
    [
      linea('BG SURTIDO BAGLEY 400G', 2, 2740.00, 6299.27, descuento: 5),
      linea('BG GALL SURTIDO LIA 400G', 3, 1680.69, 5795.88, descuento: 5),
      for (var i = 0; i < 6; i++) linea('BG ALF AGUILA MINITORTA ${i + 1} 69G', 3, 1215.44, 4412.06),
      linea('FANT ALF TRIPLE CHOC 85GR (12)', 12, 716.08, 10397.51),
      linea('FANT ALF TRIPLE BLANCO 85GR (12)', 12, 716.08, 10397.51),
      linea('TABES LAS HOJAS TABACO 50GR (100)', 10, 3307.43, 47894.70, internos: 7874.80),
    ],
    {'subtotal': 82134.26, 'impuestos_internos': 7874.80, 'iva_total': 17248.19, 'total': 107257.25},
  );

  FacturaNormalizada normalizar(Map<String, dynamic> json, {ModoImportes? preferido}) {
    final lectura = leerRespuestaDeFacturas(json);
    expect(lectura.facturas, hasLength(1));
    return normalizarFactura(lectura.facturas.single, preferido: preferido);
  }

  group('leerRespuestaDeFacturas', () {
    test('lee la cabecera, las líneas y el pie', () {
      final f = leerRespuestaDeFacturas(elpar).facturas.single;
      expect(f.proveedorCuit, '30708174757');
      expect(f.tipo, 'A');
      expect(f.numero, '0011-00266439');
      expect(f.fecha, DateTime(2026, 7, 24));
      expect(f.condicionPago, 'cuenta_corriente');
      expect(f.lineas, hasLength(10));
      expect(f.lineas.first.importeCentavos, 488504);
      expect(f.lineas.first.precioUnitarioCentavos, 171405);
      expect(f.lineas.first.alicuotaBp, 2100);
      expect(f.pie.totalCentavos, 4405410);
      expect(f.pie.percepcionesCentavos, 36110);
    });

    test('acepta números escritos como texto, con coma o con punto de miles', () {
      final f = leerRespuestaDeFacturas({
        'facturas': [
          {
            'lineas': [
              {'descripcion': 'a', 'importe': '1.234,56', 'cantidad': '2'},
              {'descripcion': 'b', 'importe': '1,234.56'},
              {'descripcion': 'c', 'importe': '\$ 99,5'},
            ],
            'pie': {'total': '3.000,00'},
          },
        ],
      }).facturas.single;
      expect(f.lineas.map((l) => l.importeCentavos), [123456, 123456, 9950]);
      expect(f.pie.totalCentavos, 300000);
    });

    test('acepta la fecha como dd/mm/aaaa y descarta una fecha imposible', () {
      DateTime? fecha(String t) => leerRespuestaDeFacturas({
            'facturas': [
              {'fecha': t, 'lineas': [], 'pie': {}},
            ],
          }).facturas.single.fecha;
      expect(fecha('25/08/2026'), DateTime(2026, 8, 25));
      expect(fecha('31/13/2026'), isNull);
      expect(fecha('ayer'), isNull);
    });

    test('un CUIT que no tiene 11 dígitos queda en null (no se adivina)', () {
      final f = leerRespuestaDeFacturas({
        'facturas': [
          {'proveedor': {'cuit': '30-7081747'}, 'lineas': [], 'pie': {}},
        ],
      }).facturas.single;
      expect(f.proveedorCuit, isNull);
    });

    test('una línea rota se descarta y se avisa; las demás siguen', () {
      final f = leerRespuestaDeFacturas({
        'facturas': [
          {
            'lineas': [
              {'descripcion': 'buena', 'importe': 100},
              {'descripcion': 'sin importe'},
              'basura',
            ],
            'pie': {},
          },
        ],
      }).facturas.single;
      expect(f.lineas, hasLength(1));
      expect(f.advertencias.single, contains('2 línea(s)'));
    });

    test('el descuento del pie se toma en positivo aunque la IA lo mande negativo', () {
      final f = leerRespuestaDeFacturas({
        'facturas': [
          {'lineas': [], 'pie': {'descuento_global': -3514.12}},
        ],
      }).facturas.single;
      expect(f.pie.descuentoGlobalCentavos, 351412);
    });

    test('una respuesta sin facturas, o con otra forma, no rompe y avisa', () {
      for (final json in <Object?>[null, 'hola', {'otra': 1}, {'facturas': []}]) {
        final r = leerRespuestaDeFacturas(json);
        expect(r.facturas, isEmpty);
        expect(r.advertencias, isNotEmpty);
      }
    });

    test('una foto con dos facturas devuelve las dos', () {
      final dos = {
        'facturas': [
          {'numero': '1', 'lineas': [], 'pie': {}},
          {'numero': '2', 'lineas': [], 'pie': {}},
        ],
      };
      expect(leerRespuestaDeFacturas(dos).facturas.map((f) => f.numero), ['1', '2']);
    });
  });

  group('normalizarFactura', () {
    test('Elpar (neto): cierra, y el costo sale con IVA y la percepción repartida', () {
      final n = normalizar(elpar);
      expect(n.modo, ModoImportes.neto);
      expect(n.cierra, isTrue);
      expect(n.lineasSospechosas, isEmpty);
      // El yogur de frutilla: $1.231 por unidad, igual que en las cuentas puras.
      expect(costosDeFactura(n.factura)[7].costoUnitarioCentavos, 123100);
    });

    test('Puelche (neto, con la línea de descuento aparte): el 10 % informativo no se vuelve a descontar', () {
      final n = normalizar(puelche());
      expect(n.modo, ModoImportes.neto);
      expect(n.cierra, isTrue);
      expect(n.control!.diferenciaCentavos, 0);
      expect(n.lineasSospechosas, isEmpty); // 6 × 1.660,64 ya da el importe sin el 10 %
      expect(costosDeFactura(n.factura).map((c) => c.costoUnitarioCentavos), [212200, 129900, 129900, 190900]);
    });

    test('el descuento como línea en negativo da lo mismo que el descuento del pie', () {
      final comoLinea = normalizar(puelche(descuentoComoLinea: true));
      final delPie = normalizar(puelche());
      expect(comoLinea.factura.descuentoGlobalCentavos, delPie.factura.descuentoGlobalCentavos);
      expect(comoLinea.factura.lineas, hasLength(4)); // la línea de descuento no es un producto
      expect(comoLinea.cierra, isTrue);
    });

    test('Serra (importe con IVA e impuestos internos adentro): prueba "neto", no cierra, y elige la forma que sí', () {
      final n = normalizar(serra, preferido: ModoImportes.neto);
      expect(n.modo, ModoImportes.conIvaEInternos);
      expect(n.cierra, isTrue);
      expect(n.lineasSospechosas, isEmpty);
      final costos = costosDeFactura(n.factura);
      expect(costos.last.costoUnitarioCentavos, 479000); // el tabaco: $4.790 con IVA e internos
      // Los internos del pie (7.874,80) ya están en la línea del tabaco: no se cuentan dos veces.
      expect(n.factura.internosAlPieCentavos, 0);
    });

    test('con IVA incluido y los internos y la percepción solo al pie (estilo Bebidas del Lago): elige "conIva"', () {
      final n = normalizar(factura(
        [linea('Cerveza lata x24', 1, 12100, 12100), linea('Cerveza lata x24 (2)', 2, 12100, 24200)],
        {'impuestos_internos': 1000, 'percepciones': 363, 'total': 37663},
      ));
      expect(n.modo, ModoImportes.conIva);
      expect(n.cierra, isTrue);
      expect(n.factura.internosAlPieCentavos, 100000);
    });

    test('el combo con sus componentes en cero no suma dos veces', () {
      final n = normalizar(factura(
        [
          linea('COMBO LATONES - BAJO DROP ABRIL', 1, 72039.5, 72039.5),
          linea('4UN BUDWEISER CAN 4X4 710CC', null, 32435.39, 0, detalle: true),
          linea('4UN STELLA ARTOIS CAN 4X4 710CC', null, 48446.37, 0.0),
        ],
        {'total': 87167.80}, // 72.039,50 + IVA 21 %
      ));
      expect(n.lineas, hasLength(1));
      expect(n.cierra, isTrue);
    });

    test('un dígito mal leído: ninguna forma cierra, y señala la línea donde mirar', () {
      final n = normalizar(puelche(importePrimera: 33312.83)); // 100 pesos de más
      expect(n.cierra, isFalse);
      expect(n.control, isNotNull);
      expect(n.control!.diferenciaCentavos, greaterThan(10000));
      expect(n.lineasSospechosas, [0]);
    });

    test('sin total impreso no se puede controlar: usa la forma preferida (o neto) y avisa con cierra = false', () {
      final json = factura([linea('algo', 1, 100, 100)], {});
      expect(normalizar(json).control, isNull);
      expect(normalizar(json).cierra, isFalse);
      expect(normalizar(json, preferido: ModoImportes.conIva).modo, ModoImportes.conIva);
    });

    test('una factura sin líneas no tiene costos ni rompe', () {
      final n = normalizar(factura([], {'total': 0}));
      expect(n.factura.lineas, isEmpty);
      expect(n.lineasSospechosas, isEmpty);
    });

    test('una cantidad con decimales o ausente cuenta como al menos una unidad', () {
      final n = normalizar(factura([linea('sin cantidad', null, null, 100), linea('media', 0.5, null, 100)], {'total': 242}));
      expect(n.factura.lineas.map((l) => l.unidades), [1, 1]);
    });
  });
}
