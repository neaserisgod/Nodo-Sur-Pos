import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/faltantes_cierre.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  group('sin la fila de reglas del negocio (un celular al que no le llegó por la sync)', () {
    // El dueño, 2026-10-14: "no guarda". Un update sobre cero filas no hacía nada y la pantalla decía "guardado".
    setUp(() => db.delete(db.configuracionNegocioTabla).go());

    test('guardar la crea con el id fijo de la fila única y guarda lo pedido', () async {
      await configurarNombreComercio(db, 'Barbería Lucho');
      final filas = await db.select(db.configuracionNegocioTabla).get();
      expect(filas, hasLength(1));
      expect(filas.single.nombreComercio, 'Barbería Lucho');
      expect(filas.single.globalId, globalIdConfiguracionNegocio);
      expect(filas.single.actualizadoEn!.isAfter(DateTime.fromMillisecondsSinceEpoch(0)), isTrue, reason: 'sube por la sync');
    });

    test('lo que no se tocó queda como se venía mostrando', () async {
      final antes = await configuracionNegocioActual(db);
      await configurarPasoRedondeo(db, 5000);
      final despues = await configuracionNegocioActual(db);
      expect(despues.pasoRedondeoCentavos, 5000);
      expect(despues.recargoPrimerAtadoCentavos, antes.recargoPrimerAtadoCentavos);
      expect(despues.pasoTurnosMinutos, antes.pasoTurnosMinutos);
    });

    test('la Agenda también se guarda, y dos escrituras no duplican la fila', () async {
      final c = await configAgendaActual(db);
      await guardarConfigAgenda(db, ConfigAgenda(horario: c.horario, pasoMinutos: 30, sena: c.sena, aliasSena: c.aliasSena, titularSena: c.titularSena));
      await configurarNombreComercio(db, 'Estética Ana');
      final filas = await db.select(db.configuracionNegocioTabla).get();
      expect(filas, hasLength(1));
      expect(filas.single.pasoTurnosMinutos, 30);
      expect(filas.single.nombreComercio, 'Estética Ana');
    });
  });

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
