// El formato real de SEPA (ZIP nacional -> un ZIP por comercio -> tres CSV
// separados por "|") se confirmó bajando un archivo real el 2026-09-14 —
// ver el comentario de cabecera de `comparador_precios.dart`. Acá se
// fabrica una muestra chica en memoria con ESE mismo esquema en vez de
// commitear un binario de 330MB: exactamente lo mismo que se probaría
// bajando el archivo real, pero legible y versionable.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/servicios/comparador_precios.dart';
import '../helpers/base_para_tests.dart';

/// Arma un CSV pipe-delimited con BOM, igual que los archivos reales de
/// SEPA — [filas] no incluye el encabezado, que sale de [columnas].
String _csv(List<String> columnas, List<List<String>> filas) {
  final buffer = StringBuffer('﻿${columnas.join('|')}\n');
  for (final fila in filas) {
    buffer.writeln(fila.join('|'));
  }
  return buffer.toString();
}

Uint8List _zipDe(Map<String, String> archivos) {
  final archive = Archive();
  for (final entrada in archivos.entries) {
    final bytes = utf8.encode(entrada.value);
    archive.addFile(ArchiveFile(entrada.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// El ZIP nacional de muestra: La Anónima (comercio 2, seguido) con dos
/// sucursales en Bariloche y una en Buenos Aires, Carrefour (comercio 10,
/// seguido) con una sucursal en Bariloche, y un comercio no seguido (99)
/// con contenido inválido — si el parser alguna vez llegara a intentar
/// decodificarlo, el test fallaría con una excepción en vez de silencioso.
Uint8List _zipNacionalDeMuestra() {
  final laAnonima = _zipDe({
    'comercio.csv': _csv(
      ['id_comercio', 'id_bandera', 'comercio_bandera_nombre'],
      [
        ['2', '1', 'La Anonima'],
      ],
    ),
    'sucursales.csv': _csv(
      ['id_comercio', 'id_bandera', 'id_sucursal', 'sucursales_localidad', 'sucursales_provincia'],
      [
        ['2', '1', '008', 'San Carlos de Bariloche', 'AR-R'],
        ['2', '1', '009', 'San Carlos de Bariloche', 'AR-R'],
        ['2', '1', '500', 'CAPITAL FEDERAL', 'AR-C'],
      ],
    ),
    'productos.csv': _csv(
      [
        'id_comercio',
        'id_bandera',
        'id_sucursal',
        'id_producto',
        'productos_ean',
        'productos_descripcion',
        'productos_precio_lista',
      ],
      [
        // Misma EAN en dos sucursales de Bariloche, precios distintos —
        // tiene que promediar: (1000 + 1400) / 2 = 1200.
        ['2', '1', '008', 'AAA111', '1', 'PRODUCTO A', '1000.00'],
        ['2', '1', '009', 'AAA111', '1', 'PRODUCTO A', '1400.00'],
        // Sucursal de Buenos Aires: no es Bariloche, tiene que quedar
        // afuera aunque sea un precio mucho más bajo (si entrara, el
        // promedio de arriba daría distinto).
        ['2', '1', '500', 'AAA111', '1', 'PRODUCTO A', '1.00'],
      ],
    ),
  });

  final carrefour = _zipDe({
    'comercio.csv': _csv(
      ['id_comercio', 'id_bandera', 'comercio_bandera_nombre'],
      [
        ['10', '1', 'Hipermercado Carrefour'],
      ],
    ),
    'sucursales.csv': _csv(
      ['id_comercio', 'id_bandera', 'id_sucursal', 'sucursales_localidad', 'sucursales_provincia'],
      [
        ['10', '1', '149', 'Bariloche', 'AR-R'],
      ],
    ),
    'productos.csv': _csv(
      [
        'id_comercio',
        'id_bandera',
        'id_sucursal',
        'id_producto',
        'productos_ean',
        'productos_descripcion',
        'productos_precio_lista',
      ],
      [
        ['10', '1', '149', 'BBB222', '1', 'PRODUCTO B', '2000.00'],
      ],
    ),
  });

  final comercioNoSeguido = Uint8List.fromList(utf8.encode('esto no es un zip válido'));

  final nacional = Archive();
  nacional.addFile(
    ArchiveFile('2026-09-14/sepa_1_comercio-sepa-2_2026-09-14_09-05-10.zip', laAnonima.length, laAnonima),
  );
  nacional.addFile(
    ArchiveFile('2026-09-14/sepa_2_comercio-sepa-10_2026-09-14_01-05-07.zip', carrefour.length, carrefour),
  );
  nacional.addFile(
    ArchiveFile(
      '2026-09-14/sepa_1_comercio-sepa-99_2026-09-14_09-05-10.zip',
      comercioNoSeguido.length,
      comercioNoSeguido,
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(nacional));
}

void main() {
  late AppDatabase db;

  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  test(
    'solo entran sucursales de Bariloche, promediadas entre sí, de los comercios seguidos',
    () async {
      await actualizarComparacionPreciosDesdeZip(db, _zipNacionalDeMuestra());

      final filas = await db.select(db.preciosReferenciaExterna).get();
      expect(filas, hasLength(2));

      final laAnonima = filas.firstWhere((f) => f.comercio == 'La Anonima');
      expect(laAnonima.codigoBarras, 'AAA111');
      expect(laAnonima.precioCentavos, 120000); // (1000 + 1400) / 2, en centavos

      final carrefour = filas.firstWhere((f) => f.comercio == 'Hipermercado Carrefour');
      expect(carrefour.codigoBarras, 'BBB222');
      expect(carrefour.precioCentavos, 200000);
    },
  );

  test('una corrida nueva reemplaza la anterior, no acumula', () async {
    await actualizarComparacionPreciosDesdeZip(db, _zipNacionalDeMuestra());
    await actualizarComparacionPreciosDesdeZip(db, _zipNacionalDeMuestra());

    final filas = await db.select(db.preciosReferenciaExterna).get();
    expect(filas, hasLength(2));
  });
}
