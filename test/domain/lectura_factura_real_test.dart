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
}
