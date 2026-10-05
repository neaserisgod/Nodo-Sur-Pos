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
}

