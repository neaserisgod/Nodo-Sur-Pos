import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import '../helpers/base_para_tests.dart';

AppDatabase abrirBaseDePrueba() => baseDeTest();

void main() {
  // Bug real (2026-09-14): se agregó un paso `if (from < 28) { ... }` a
  // `onUpgrade` sin subir `schemaVersion` de 27 a 28 — el paso nunca
  // corría porque drift solo mira `schemaVersion`, no lo que hay escrito
  // adentro de `onUpgrade`. Invisible en cualquier test de acá arriba
  // porque todos abren con `NativeDatabase.memory()`, que siempre pasa por
  // `onCreate` (`createAll()`, crea todo de una sin importar el número de
  // versión) — nunca por `onUpgrade`, que es donde vive el bug real: una
  // base YA EXISTENTE (como la real de el dueño) se queda pegada en la
  // versión vieja para siempre, sin la tabla ni la sección nuevas, sin
  // ningún error visible. Sigue sin haber infraestructura de test que abra
  // una base vieja de verdad y la actualice (`drift_dev schema dump` +
  // `SchemaVerifier` sería lo correcto) — este test es más barato: si
  // alguien agrega un paso `from < N` nuevo y se olvida de subir
  // `schemaVersion` a N, esto falla.
  test(
    'schemaVersion nunca queda por debajo del paso de migración más alto en onUpgrade',
    () {
      final fuente = File('lib/data/database.dart').readAsStringSync();
      final pasos = RegExp(r'from < (\d+)')
          .allMatches(fuente)
          .map((m) => int.parse(m.group(1)!));
      final pasoMasAlto = pasos.reduce((a, b) => a > b ? a : b);

      final schemaVersion = baseDeTest().schemaVersion;
      expect(
        schemaVersion,
        greaterThanOrEqualTo(pasoMasAlto),
        reason:
            'Hay un paso "from < $pasoMasAlto" en onUpgrade pero schemaVersion '
            'es $schemaVersion — ese paso nunca va a correr.',
      );
    },
  );

  group('esquema y semillas al crear la base', () {
    late AppDatabase db;

    setUp(() => db = abrirBaseDePrueba());
    tearDown(() => db.close());

    test('siembra exactamente 2 cajas: normal y lata (Regla 10)', () async {
      final cajas = await db.select(db.cajas).get();
      expect(cajas, hasLength(2));
      expect(cajas.where((c) => c.esLata).length, 1);
      expect(cajas.where((c) => !c.esLata).length, 1);
    });

    test('siembra los 2 medios de pago base, efectivo primero', () async {
      final medios = await db.select(db.mediosDePago).get();
      expect(medios, hasLength(2));
      final efectivo = medios.singleWhere((m) => m.esEfectivo);
      expect(efectivo.nombre, 'Efectivo');
      final virtual = medios.singleWhere((m) => !m.esEfectivo);
      expect(virtual.nombre, 'Mercado Pago');
    });

    test('siembra los 15 proveedores de la Regla 16 con su código, todos activos', () async {
      final proveedores = await db.select(db.proveedores).get();
      expect(proveedores, hasLength(15));
      expect(proveedores.every((p) => p.activo), true);
      final codigos = proveedores.map((p) => p.codigo).toSet();
      expect(codigos, {
        'S', 'SC', 'F', 'C', 'W', 'A', 'P', 'L', 'E', 'D', 'K', 'I', 'Z', 'X', 'M',
      });
      final serra = proveedores.singleWhere((p) => p.codigo == 'S');
      expect(serra.nombre, 'Distribuidora');
      final mazzota = proveedores.singleWhere((p) => p.codigo == 'F');
      expect(mazzota.nombre, 'Fiambrería');
    });

    test('siembra el producto "Varios" sin precio fijo (Regla 5)', () async {
      final varios = await (db.select(db.productos)
            ..where((p) => p.esVarios.equals(true)))
          .getSingle();
      expect(varios.nombre, 'Varios');
      expect(varios.precioCentavos, isNull);
    });

    test('siembra un usuario para que la apertura de caja no arranque vacía (Regla 18)', () async {
      final usuarios = await db.select(db.usuarios).get();
      expect(usuarios, isNotEmpty);
      expect(usuarios.first.nombre, 'Dueño');
    });

    test('siembra las 11 categorías reales del catálogo (Regla 14), no proveedores', () async {
      final categorias = await db.select(db.categorias).get();
      expect(categorias, hasLength(11));
      final nombres = categorias.map((c) => c.nombre).toSet();
      expect(nombres, {
        'Almacén', 'Bebidas', 'Cervezas', 'Gaseosas', 'Vinos', 'Cigarrillos',
        'Golosinas', 'Galletitas y panificados', 'Yerbas y té',
        'Higiene y limpieza', 'Fiambres',
      });
      // Distribuidora, Golosinas Oeste y Coca-Cola son proveedores (Regla 16), no categorías.
      expect(nombres.contains('Distribuidora'), false);
      expect(nombres.contains('Golosinas Oeste'), false);
      expect(nombres.contains('Coca-Cola'), false);
    });

    test('las categorías sin referencia de markup quedan en 0, no un dato inventado', () async {
      final vinos =
          await (db.select(db.categorias)..where((c) => c.nombre.equals('Vinos'))).getSingle();
      expect(vinos.markupDefaultBp, 0);

      final fiambres =
          await (db.select(db.categorias)..where((c) => c.nombre.equals('Fiambres'))).getSingle();
      expect(fiambres.markupDefaultBp, 9000);
    });
  });

  group('integridad referencial (PRAGMA foreign_keys)', () {
    late AppDatabase db;

    setUp(() => db = abrirBaseDePrueba());
    tearDown(() => db.close());

    test('no deja insertar una línea de venta con venta_id inexistente', () async {
      expect(
        () => db.into(db.lineasDeVenta).insert(
              LineasDeVentaCompanion.insert(
                ventaId: 999999,
                nombreProductoFoto: 'Fantasma',
                precioUnitarioCentavos: 1000,
              ),
            ),
        throwsA(anything),
      );
    });
  });

  group('flujo mínimo de una venta', () {
    late AppDatabase db;

    setUp(() => db = abrirBaseDePrueba());
    tearDown(() => db.close());

    test('abrir sesión, cargar una venta con línea y pago, y leerla de vuelta', () async {
      final usuarioId = await db.into(db.usuarios).insert(
            UsuariosCompanion.insert(nombre: 'Dueño'),
          );

      final cajaNormal =
          await (db.select(db.cajas)..where((c) => c.esLata.equals(false)))
              .getSingle();

      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 15000000, // $150.000
            ),
          );

      final coca = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola 500ml',
              precioCentavos: const Value(112000),
              costoCentavos: const Value(80000),
            ),
          );

      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: 224000,
              totalCentavos: 224000,
            ),
          );

      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              productoId: Value(coca),
              nombreProductoFoto: 'Coca-Cola 500ml',
              cantidad: const Value(2),
              precioUnitarioCentavos: 112000,
              costoUnitarioCentavos: const Value(80000),
            ),
          );

      final medioEfectivo = await (db.select(db.mediosDePago)
            ..where((m) => m.esEfectivo.equals(true)))
          .getSingle();

      await db.into(db.pagos).insert(
            PagosCompanion.insert(
              ventaId: ventaId,
              medioPagoId: medioEfectivo.id,
              montoCentavos: 224000,
            ),
          );

      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormal.id,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              montoCentavos: 224000,
              ventaId: Value(ventaId),
              medioPagoId: Value(medioEfectivo.id),
            ),
          );

      final ventaGuardada = await (db.select(db.ventas)
            ..where((v) => v.id.equals(ventaId)))
          .getSingle();
      expect(ventaGuardada.totalCentavos, 224000);

      final lineas = await (db.select(db.lineasDeVenta)
            ..where((l) => l.ventaId.equals(ventaId)))
          .get();
      expect(lineas, hasLength(1));
      expect(lineas.single.costoUnitarioCentavos, 80000);

      final movimientos = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.sesionCajaId.equals(sesionId)))
          .get();
      expect(movimientos, hasLength(1));
      expect(movimientos.single.cajaId, cajaNormal.id);
    });

    test('una línea sin costo cargado guarda null, no 0 (Regla 5/9)', () async {
      final usuarioId =
          await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
            ),
          );
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: 50000,
              totalCentavos: 50000,
            ),
          );

      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto recién escaneado',
              precioUnitarioCentavos: 50000,
              // costoUnitarioCentavos deliberadamente ausente.
            ),
          );

      final linea = await (db.select(db.lineasDeVenta)
            ..where((l) => l.ventaId.equals(ventaId)))
          .getSingle();
      expect(linea.costoUnitarioCentavos, isNull);
    });
  });
}
