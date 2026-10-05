import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/factura_compra.dart';
import 'package:la_plazoleta/domain/lectura_factura.dart';

/// La primera lectura REAL de Gemini (2026-10-05): factura A de Serra 0051-00194239, copiada con "Copiar lectura" desde la pantalla de
/// prueba y guardada tal cual en `test/fixtures/`. Es la prueba de que lo que devuelve la IA de verdad lo entiende el código.
void main() {
  late Map<String, dynamic> json;

  setUp(() {
    json = jsonDecode(File('test/fixtures/lectura_serra_0051_00194239.json').readAsStringSync()) as Map<String, dynamic>;
  });

  test('se lee la cabecera y las 17 líneas, sin advertencias', () {
    final lectura = leerRespuestaDeFacturas(json);
    final f = lectura.facturas.single;
    expect(lectura.advertencias, isEmpty);
    expect(f.advertencias, isEmpty);
    expect(f.proveedorCuit, '30670378213');
    expect(f.tipo, 'A');
    expect(f.numero, '0051-00194239');
    expect(f.fecha, DateTime(2026, 8, 31));
    expect(f.condicionPago, 'cuenta_corriente');
    expect(f.lineas, hasLength(17));
    expect(f.pie.totalCentavos, 9467688);
  });

  test('el sistema elige solo la forma de leer los importes (con IVA adentro) y cierra al centavo', () {
    final n = normalizarFactura(leerRespuestaDeFacturas(json).facturas.single);
    expect(n.modo, ModoImportes.conIva);
    expect(n.cierra, isTrue);
    expect(n.control!.diferenciaCentavos, 0);
    expect(n.control!.totalCalculadoCentavos, 9467688);
    expect(n.lineasSospechosas, isEmpty); // cantidad × precio da el neto de cada línea
  });

  test('el costo por unidad sale con el IVA y redondeado al peso hacia arriba', () {
    final n = normalizarFactura(leerRespuestaDeFacturas(json).facturas.single);
    final costos = costosDeFactura(n.factura);
    // Sal fina: 4 unidades, 4.545,82 con IVA → 1.136,46 → $1.137.
    expect(costos.first.costoUnitarioCentavos, 113700);
    // Alfajor Águila minitorta: 3 unidades, 4.412,06 → 1.470,69 → $1.471.
    expect(costos[8].costoUnitarioCentavos, 147100);
    // Papel OCB: 1 unidad, 21.498,21 → $21.499.
    expect(costos[15].costoUnitarioCentavos, 2149900);
  });

  test('un dígito mal leído en esta misma factura NO cierra y señala la línea', () {
    final lineas = (json['facturas'] as List).single['lineas'] as List;
    (lineas[3] as Map<String, dynamic>)['importe'] = 3359.04; // 100 pesos de más en "Media tarde"
    final n = normalizarFactura(leerRespuestaDeFacturas(json).facturas.single);
    expect(n.cierra, isFalse);
    expect(n.control!.diferenciaCentavos, greaterThan(9000));
    expect(n.lineasSospechosas, [3]);
  });

  group('Puelche 0148-00034664 (la segunda lectura real: descuento general aparte, contado)', () {
    late Map<String, dynamic> puelche;

    setUp(() {
      puelche = jsonDecode(File('test/fixtures/lectura_puelche_0148_00034664.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('se lee la cabecera, las 7 líneas y el descuento del pie, sin advertencias', () {
      final f = leerRespuestaDeFacturas(puelche).facturas.single;
      expect(f.advertencias, isEmpty);
      expect(f.proveedorCuit, '30538048190');
      expect(f.numero, '0148-00034664');
      expect(f.fecha, DateTime(2026, 10, 1));
      expect(f.condicionPago, 'contado');
      expect(f.lineas, hasLength(7));
      expect(f.pie.descuentoGlobalCentavos, 164487);
      expect(f.pie.totalCentavos, 3781572);
    });

    test('cierra con el total impreso (2 centavos de redondeo del proveedor), con los importes sin IVA y sin líneas sospechosas', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(puelche).facturas.single);
      expect(n.modo, ModoImportes.neto);
      expect(n.cierra, isTrue);
      expect(n.control!.diferenciaCentavos.abs(), lessThanOrEqualTo(2));
      // Los precios con 3 decimales (534,076) no dan falsas alarmas.
      expect(n.lineasSospechosas, isEmpty);
    });

    test('el descuento general baja el costo de cada producto y el IVA se suma después', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(puelche).facturas.single);
      final costos = costosDeFactura(n.factura);
      // Fibra: 5 unidades, 2.670,38 − su parte del descuento + IVA = 3.069,60 → 613,92 → $614 c/u.
      expect(costos.first.costoUnitarioCentavos, 61400);
      expect(costos.map((c) => c.costoUnitarioCentavos), [61400, 189400, 189400, 182000, 658600, 658600, 122700]);
    });

    test('un dígito mal leído en esta factura también se atrapa', () {
      final lineas = (puelche['facturas'] as List).single['lineas'] as List;
      (lineas[3] as Map<String, dynamic>)['importe'] = 8014.27; // 100 pesos de más en el rollo de cocina
      final n = normalizarFactura(leerRespuestaDeFacturas(puelche).facturas.single);
      expect(n.cierra, isFalse);
      expect(n.lineasSospechosas, [3]);
    });
  });

  group('Serra 0065-00076671 (la tercera lectura real: cigarrillos, impuestos internos por línea)', () {
    late Map<String, dynamic> cigarrillos;

    setUp(() {
      cigarrillos = jsonDecode(File('test/fixtures/lectura_serra_cigarrillos_0065_00076671.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('se leen las 8 líneas con sus impuestos internos y el pie', () {
      final f = leerRespuestaDeFacturas(cigarrillos).facturas.single;
      expect(f.advertencias, isEmpty);
      expect(f.lineas, hasLength(8));
      expect(f.lineas.first.internosCentavos, 4110740);
      expect(f.pie.internosCentavos, 26687780);
      expect(f.pie.totalCentavos, 35306961);
      expect(f.condicionPago, 'contado');
    });

    test('elige solo "IVA e internos adentro", cierra con 1 centavo y no cuenta los internos dos veces', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(cigarrillos).facturas.single);
      expect(n.modo, ModoImportes.conIvaEInternos);
      expect(n.cierra, isTrue);
      expect(n.control!.diferenciaCentavos.abs(), lessThanOrEqualTo(1));
      expect(n.lineasSospechosas, isEmpty);
      // Los internos del pie (266.877,80) son la suma de los de las líneas: no se vuelven a sumar.
      expect(n.factura.internosAlPieCentavos, 0);
    });

    test('el costo de cada atado es el importe de la línea entre sus unidades, redondeado al peso hacia arriba', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(cigarrillos).facturas.single);
      final costos = costosDeFactura(n.factura);
      // Marlboro KS: 54.537,92 / 10 = 5.453,79 → $5.454. Crafted Red (20 atados): 65.837,96 / 20 = 3.291,90 → $3.292.
      expect(costos.map((c) => c.costoUnitarioCentavos), [545400, 206400, 329200, 329200, 420600, 525800, 486500, 358700]);
      expect(costos.first.internosCentavos, 4110740);
    });

    test('los impuestos internos son la mayor parte del costo de un atado', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(cigarrillos).facturas.single);
      final c = costosDeFactura(n.factura).first;
      expect(c.internosCentavos * 100 ~/ c.totalCentavos, greaterThan(70)); // más del 70 % del costo son impuestos internos
    });
  });

  group('Coca-Cola 3579-00021534 (la cuarta lectura real: foto de costado, Factura B, descuento como monto)', () {
    late Map<String, dynamic> coca;

    setUp(() {
      coca = jsonDecode(File('test/fixtures/lectura_cocacola_3579_00021534.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('se lee entera aunque la foto estaba de costado, y el "porcentaje" de 3.230,78 pasa a ser un monto', () {
      final f = leerRespuestaDeFacturas(coca).facturas.single;
      expect(f.advertencias, isEmpty);
      expect(f.proveedorCuit, '30529135943');
      expect(f.tipo, 'B');
      expect(f.numero, '3579-00021534');
      expect(f.condicionPago, 'contado');
      expect(f.lineas, hasLength(4));
      // Un descuento "de 3230,78 %" no existe: era el monto.
      expect(f.lineas.first.descuentoPct, isNull);
      expect(f.lineas.first.descuentoImporteCentavos, 323078);
      expect(f.pie.percepcionesCentavos, 542769);
    });

    test('cierra al centavo y NO marca líneas sospechosas (16.153,85 − 3.230,78 = 12.923,07)', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(coca).facturas.single);
      expect(n.cierra, isTrue);
      expect(n.control!.diferenciaCentavos, 0);
      expect(n.lineasSospechosas, isEmpty);
    });

    test('el costo de cada pack lleva su parte de la percepción de \$5.427,69', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(coca).facturas.single);
      final costos = costosDeFactura(n.factura);
      expect(costos.fold<int>(0, (a, c) => a + c.percepcionesCentavos), 542769);
      // 12.923,07 + 1.356,92 = 14.279,99 → $14.280 por pack.
      expect(costos.map((c) => c.costoUnitarioCentavos), [1428000, 1428000, 1428000, 1428000]);
    });

    test('con "× 6" (un pack son 6 latas) el costo por lata es \$2.380', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(coca).facturas.single);
      final porLata = costosDeFactura(conUnidadesPorCantidad(n.factura, [6, 6, 6, 6]));
      expect(porLata.map((c) => c.costoUnitarioCentavos), [238000, 238000, 238000, 238000]);
    });
  });

  group('Manaos / La Magdalena (la quinta lectura real: DOS facturas en una foto)', () {
    late Map<String, dynamic> manaos;

    setUp(() {
      manaos = jsonDecode(File('test/fixtures/lectura_manaos_dos_por_foto.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('devuelve las dos facturas separadas, cada una con su número y su fecha', () {
      final facturas = leerRespuestaDeFacturas(manaos).facturas;
      expect(facturas.map((f) => f.numero), ['0001-00046896', '0001-00048107']);
      expect(facturas.map((f) => f.fecha), [DateTime(2026, 9, 3), DateTime(2026, 10, 1)]);
      expect(facturas.map((f) => f.lineas.length), [3, 2]);
    });

    test('un CUIT con un dígito de más (la carbónica) NO se cree: queda sin leer y avisa que se elija el proveedor a mano', () {
      for (final f in leerRespuestaDeFacturas(manaos).facturas) {
        expect(f.proveedorCuit, isNull);
        expect(f.advertencias.single, contains('no es válido'));
      }
    });

    test('las dos cierran al centavo, con los impuestos internos que vienen solo al pie', () {
      for (final f in leerRespuestaDeFacturas(manaos).facturas) {
        final n = normalizarFactura(f);
        expect(n.cierra, isTrue);
        expect(n.cierraConRedondeo, isFalse);
        expect(n.control!.diferenciaCentavos, 0);
        expect(n.factura.internosAlPieCentavos, f.pie.internosCentavos);
      }
    });

    test('el costo de cada pack lleva IVA y su parte de los impuestos internos del pie', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(manaos).facturas.first);
      // Alvura: 7.694,95 + IVA 1.615,94 + su parte de los internos del pie = 9.487,40 → $9.488 el pack.
      expect(costosDeFactura(n.factura).map((c) => c.costoUnitarioCentavos), [948800, 990700, 990700]);
    });
  });

  group('Bebidas del Lago (la sexta lectura real: matriz de puntos, dos por foto, combos)', () {
    late Map<String, dynamic> lago;

    setUp(() {
      lago = jsonDecode(File('test/fixtures/lectura_bebidas_del_lago_dos_por_foto.json').readAsStringSync()) as Map<String, dynamic>;
    });

    test('las líneas hijas del combo no son productos: quedan 4 por factura', () {
      for (final f in leerRespuestaDeFacturas(lago).facturas) {
        expect(f.lineas, hasLength(10));
        expect(normalizarFactura(f).lineas, hasLength(4));
      }
    });

    test('el importe de cada línea ya incluye IVA, internos y percepción: elige "todoIncluido" y no cuenta la percepción dos veces', () {
      for (final f in leerRespuestaDeFacturas(lago).facturas) {
        final n = normalizarFactura(f);
        expect(n.modo, ModoImportes.todoIncluido);
        expect(n.factura.percepcionesCentavos, 0);
        expect(n.factura.internosAlPieCentavos, 0);
        expect(costosDeFactura(n.factura).every((c) => c.percepcionesCentavos == 0), isTrue);
      }
    });

    test('cierra con el redondeo de una impresión de un decimal (18 y 21 centavos), no al centavo', () {
      final diferencias = <int>[];
      for (final f in leerRespuestaDeFacturas(lago).facturas) {
        final n = normalizarFactura(f);
        expect(n.cierra, isTrue);
        expect(n.cierraConRedondeo, isTrue);
        diferencias.add(n.control!.diferenciaCentavos);
      }
      expect(diferencias, [-18, -21]);
    });

    test('no marca líneas sospechosas aunque el precio sea por bulto y la cantidad por lata (la factura cierra)', () {
      for (final f in leerRespuestaDeFacturas(lago).facturas) {
        expect(normalizarFactura(f).lineasSospechosas, isEmpty);
      }
    });

    test('la fecha de 2023 (una factura de 2026 mal leída) se marca como dudosa; la otra no', () {
      final fechas = leerRespuestaDeFacturas(lago).facturas.map((f) => f.fecha).toList();
      final hoy = DateTime(2026, 10, 5);
      expect(fechaDudosa(fechas[0], hoy), isTrue);
      expect(fechaDudosa(fechas[1], hoy), isFalse);
    });

    test('el costo por lata es el importe de la línea entre las 6 latas, subido al peso', () {
      final n = normalizarFactura(leerRespuestaDeFacturas(lago).facturas.last);
      // Andes IPA: 13.579,80 / 6 = 2.263,30 → $2.264.
      expect(costosDeFactura(n.factura).first.costoUnitarioCentavos, 226400);
    });
  });
}

