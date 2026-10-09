import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/faltantes_cierre.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  test('configurarRecargoCigarrillos actualiza los tres montos', () async {
    await configurarRecargoCigarrillos(
      db,
      primerAtadoCentavos: 40000,
      atadoAdicionalCentavos: 15000,
      sueltoCentavos: 5000,
    );

    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.recargoPrimerAtadoCentavos, 40000);
    expect(config.recargoAtadoAdicionalCentavos, 15000);
    expect(config.recargoSueltoCentavos, 5000);
  });

  test('configurarFondoFijo actualiza configuracion_tabla, configurarPasoRedondeo la tabla de negocio', () async {
    await configurarFondoFijo(db, 20000000);
    await configurarPasoRedondeo(db, 5000);

    final config = await db.select(db.configuracionTabla).getSingle();
    expect(config.fondoFijoCentavos, 20000000);
    final negocio = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(negocio.pasoRedondeoCentavos, 5000);
  });

  test('umbral de faltantes del cierre: arranca en el valor del dominio, se cambia, y negativo no se guarda', () async {
    expect((await db.select(db.configuracionTabla).getSingle()).umbralFaltanteCentavos, umbralFaltantePorDefectoCentavos);
    await configurarUmbralFaltante(db, 1500000);
    expect((await db.select(db.configuracionTabla).getSingle()).umbralFaltanteCentavos, 1500000);
    expect(() => configurarUmbralFaltante(db, -1), throwsFormatException);
  });

  test('default de fábrica: sin producto de vuelto configurado', () async {
    final config = await configuracionNegocioActual(db);
    expect(config.productoVueltoId, isNull);
  });

  test('configurarProductoVuelto guarda el id del producto elegido', () async {
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Caramelo', precioCentavos: const Value(500)),
        );

    await configurarProductoVuelto(db, productoId);

    final config = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(config.productoVueltoId, productoId);
  });

  test('rubro: arranca sin elegir; configurarRubro lo guarda y lo marca para la sync', () async {
    expect(await rubroActual(db), isNull, reason: 'un negocio viejo no tiene rubro guardado (v63)');
    final antes = (await configuracionNegocioActual(db)).actualizadoEn;

    await configurarRubro(db, PlantillaRubro.almacen);

    expect(await rubroActual(db), PlantillaRubro.almacen);
    final config = await configuracionNegocioActual(db);
    expect(config.rubro, 'almacen');
    expect(config.actualizadoEn, isNotNull);
    if (antes != null) expect(config.actualizadoEn!.isBefore(antes), isFalse);
  });

  test('rubro guardado con una clave que esta versión no conoce: se lee como sin elegir, no rompe', () async {
    await db.update(db.configuracionNegocioTabla).write(const ConfiguracionNegocioTablaCompanion(rubro: Value('rubro_del_futuro')));
    expect(await rubroActual(db), isNull);
    // Barbería era desconocida antes de los rubros de servicios; ahora se lee.
    await db.update(db.configuracionNegocioTabla).write(const ConfiguracionNegocioTablaCompanion(rubro: Value('barberia')));
    expect(await rubroActual(db), PlantillaRubro.barberia);
  });

  test('configuracionNegocioActual devuelve defaults de fábrica si la tabla está vacía (companion sin sync)', () async {
    await db.delete(db.configuracionNegocioTabla).go();

    final config = await configuracionNegocioActual(db);
    expect(config.recargoPrimerAtadoCentavos, 30000);
    expect(config.recargoAtadoAdicionalCentavos, 10000);
    expect(config.recargoSueltoCentavos, 5000);
    expect(config.pasoRedondeoCentavos, 10000);
    expect(config.productoVueltoId, isNull);
    expect(config.rubro, '');
  });
}
