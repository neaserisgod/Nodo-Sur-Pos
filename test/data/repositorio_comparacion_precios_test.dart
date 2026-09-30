// Cobertura del cruce (Bruno, 2026-09-14: "todo lo que esté en mi
// sistema") — ver el comentario de cabecera de
// `repositorio_comparacion_precios.dart` para los dos caminos de cruce
// (código de barras exacto vs. nombre aproximado, solo para pesables).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_comparacion_precios.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  Future<void> guardarReferencia({
    required String codigoBarras,
    required String nombreProducto,
    required String comercio,
    required int precioCentavos,
    int? precioReferenciaCentavos,
    String? unidadReferencia,
  }) => db.into(db.preciosReferenciaExterna).insert(
    PreciosReferenciaExternaCompanion.insert(
      codigoBarras: codigoBarras,
      nombreProducto: Value(nombreProducto),
      comercio: comercio,
      fuente: 'sepa',
      precioCentavos: precioCentavos,
      precioReferenciaCentavos: Value(precioReferenciaCentavos),
      unidadReferencia: Value(unidadReferencia),
      actualizadoEn: DateTime.now(),
    ),
  );

  test('producto por unidad con código de barras: cruza exacto por EAN', () async {
    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Coca-Cola 500ml',
        codigoBarras: const Value('7790895001234'),
        precioCentavos: const Value(100000),
      ),
    );
    await guardarReferencia(
      codigoBarras: '7790895001234',
      nombreProducto: 'COCA COLA 500ML',
      comercio: 'La Anonima',
      precioCentavos: 120000,
    );

    final resultado = await comparacionDePrecios(db);
    expect(resultado, hasLength(1));
    expect(resultado.single.tipoCoincidencia, 'codigo');
    expect(resultado.single.preciosPorComercio, {'La Anonima': 120000});
    expect(resultado.single.mayorDiferenciaAbs, closeTo(0.2, 0.0001));
  });

  test(
    'todo lo que esté en el sistema aparece, incluso sin ninguna coincidencia (Bruno, 2026-09-14)',
    () async {
      await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Producto sin nada de referencia',
          codigoBarras: const Value('0000000000000'),
          precioCentavos: const Value(50000),
        ),
      );

      final resultado = await comparacionDePrecios(db);
      expect(resultado, hasLength(1));
      expect(resultado.single.preciosPorComercio, isEmpty);
      expect(resultado.single.mayorDiferenciaAbs, isNull);
    },
  );

  test('"Varios" nunca aparece: no tiene precio fijo que mostrar', () async {
    await db.into(db.productos).insert(
      ProductosCompanion.insert(nombre: 'Varios', esVarios: const Value(true)),
    );

    final resultado = await comparacionDePrecios(db);
    expect(resultado, isEmpty);
  });

  test('producto inactivo no aparece', () async {
    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Descontinuado',
        codigoBarras: const Value('1111111111111'),
        precioCentavos: const Value(10000),
        activo: const Value(false),
      ),
    );

    final resultado = await comparacionDePrecios(db);
    expect(resultado, isEmpty);
  });

  test(
    'pesable cruza por nombre (aproximado) contra el precio de referencia por kilo',
    () async {
      await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Banana',
          esPesable: const Value(true),
          precioPorKiloCentavos: const Value(150000),
        ),
      );
      await guardarReferencia(
        codigoBarras: '', // pesable, sin código de barras
        nombreProducto: 'BANANA ECUADOR X KG',
        comercio: 'La Anonima',
        precioCentavos: 999999, // no se usa para pesables, solo el de referencia
        precioReferenciaCentavos: 180000,
        unidadReferencia: 'kgr',
      );

      final resultado = await comparacionDePrecios(db);
      expect(resultado, hasLength(1));
      final banana = resultado.single;
      expect(banana.esPesable, isTrue);
      expect(banana.tipoCoincidencia, 'nombre');
      expect(banana.preciosPorComercio, {'La Anonima': 180000});
    },
  );

  test(
    'pesable NO cruza si la unidad de referencia no es de peso (evita comparar cosas distintas)',
    () async {
      await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Banana',
          esPesable: const Value(true),
          precioPorKiloCentavos: const Value(150000),
        ),
      );
      await guardarReferencia(
        codigoBarras: '',
        nombreProducto: 'BANANA ECUADOR X KG',
        comercio: 'La Anonima',
        precioCentavos: 999999,
        precioReferenciaCentavos: 180000,
        unidadReferencia: '1 Un', // no es peso — no se puede comparar contra precio/kilo
      );

      final resultado = await comparacionDePrecios(db);
      expect(resultado.single.preciosPorComercio, isEmpty);
    },
  );

  test(
    'nombres cortos no cruzan por contención (evita falsos positivos tipo "pan" en "empanada")',
    () async {
      await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Pan',
          esPesable: const Value(true),
          precioPorKiloCentavos: const Value(50000),
        ),
      );
      await guardarReferencia(
        codigoBarras: '',
        nombreProducto: 'EMPANADA DE CARNE X KG',
        comercio: 'La Anonima',
        precioCentavos: 0,
        precioReferenciaCentavos: 200000,
        unidadReferencia: 'kgr',
      );

      final resultado = await comparacionDePrecios(db);
      expect(resultado.single.preciosPorComercio, isEmpty);
    },
  );

  test('ordena por mayor diferencia primero, lo sin coincidencia al final', () async {
    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Diferencia chica',
        codigoBarras: const Value('1000000000001'),
        precioCentavos: const Value(100000),
      ),
    );
    await guardarReferencia(
      codigoBarras: '1000000000001',
      nombreProducto: 'X',
      comercio: 'La Anonima',
      precioCentavos: 110000, // 10% de diferencia
    );

    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Diferencia grande',
        codigoBarras: const Value('1000000000002'),
        precioCentavos: const Value(100000),
      ),
    );
    await guardarReferencia(
      codigoBarras: '1000000000002',
      nombreProducto: 'Y',
      comercio: 'La Anonima',
      precioCentavos: 200000, // 100% de diferencia
    );

    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Sin coincidencia',
        codigoBarras: const Value('1000000000003'),
        precioCentavos: const Value(100000),
      ),
    );

    final resultado = await comparacionDePrecios(db);
    expect(resultado.map((c) => c.nombre).toList(), [
      'Diferencia grande',
      'Diferencia chica',
      'Sin coincidencia',
    ]);
  });
}
