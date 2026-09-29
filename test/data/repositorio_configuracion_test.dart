import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
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

  test('configuracionNegocioActual devuelve defaults de fábrica si la tabla está vacía (companion sin sync)', () async {
    await db.delete(db.configuracionNegocioTabla).go();

    final config = await configuracionNegocioActual(db);
    expect(config.recargoPrimerAtadoCentavos, 30000);
    expect(config.recargoAtadoAdicionalCentavos, 10000);
    expect(config.recargoSueltoCentavos, 5000);
    expect(config.pasoRedondeoCentavos, 10000);
    expect(config.productoVueltoId, isNull);
  });
}
