// La configuración del negocio es una sola fila por equipo (revisión 2026-10-03). En una PC instalada de cero nacía sin
// `global_id` y nunca llegaba al celular; y si el celular ya tenía la suya, la sync insertaba una segunda fila y el
// equipo dejaba de poder leer su configuración (`getSingle`).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _tabla = 'configuracion_negocio_tabla';

Future<void> _pasar(AppDatabase desde, AppDatabase hacia) async {
  final filas = await cambiosDesde(desde, tabla: _tabla, desde: 0);
  expect(await aplicarCambios(hacia, tabla: _tabla, filas: filas), isEmpty);
}

/// Un celular que ya armó su negocio con una versión vieja: su fila tiene OTRO `global_id` (uno al azar).
Future<AppDatabase> _celularConConfiguracionPropia() async {
  final celular = AppDatabase(NativeDatabase.memory());
  await celular.update(celular.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          globalId: const Value('id-al-azar-del-celular'),
          recargoPrimerAtadoCentavos: const Value(0),
          nombreComercio: const Value('Kiosco Ana'),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
  return celular;
}

void main() {
  test('una PC nueva siembra la configuración con el id fijo y sale por la sync', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    addTearDown(pc.close);
    final filas = await cambiosDesde(pc, tabla: _tabla, desde: 0);
    expect(filas.single['global_id'], globalIdConfiguracionNegocio);
  });

  test('PC nueva y celular con su propia configuración: cada uno queda con UNA fila, y gana la más reciente', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    final celular = await _celularConConfiguracionPropia();
    addTearDown(pc.close);
    addTearDown(celular.close);

    await _pasar(pc, celular);
    await _pasar(celular, pc);

    for (final db in [pc, celular]) {
      expect(await db.select(db.configuracionNegocioTabla).get(), hasLength(1));
      final config = await configuracionNegocioActual(db);
      expect(config.nombreComercio, 'Kiosco Ana', reason: 'la del celular es más nueva que la sembrada en la PC');
      expect(config.recargoPrimerAtadoCentavos, 0);
    }

    // Después, un cambio en la PC llega al celular aunque las dos filas tengan distinto id.
    await Future<void>.delayed(const Duration(milliseconds: 1100)); // `actualizado_en` guarda segundos
    await configurarNombreComercio(pc, 'Almacén Ana');
    await _pasar(pc, celular);
    expect((await configuracionNegocioActual(celular)).nombreComercio, 'Almacén Ana');
    expect(await celular.select(celular.configuracionNegocioTabla).get(), hasLength(1));
  });

  test('el rubro viaja con la configuración (v63)', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    final celular = await _celularConConfiguracionPropia();
    addTearDown(pc.close);
    addTearDown(celular.close);
    await Future<void>.delayed(const Duration(milliseconds: 1100)); // `actualizado_en` guarda segundos
    await configurarRubro(pc, PlantillaRubro.almacen);
    await _pasar(pc, celular);
    expect(await rubroActual(celular), PlantillaRubro.almacen);
  });

  test('un equipo sin actualizar (sin la columna rubro) que edita otra cosa no le borra el rubro al que sí lo tiene', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    final celular = await _celularConConfiguracionPropia();
    addTearDown(pc.close);
    addTearDown(celular.close);
    await configurarRubro(celular, PlantillaRubro.almacen);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await configurarNombreComercio(pc, 'Almacén Ana');
    // Lo que manda una versión anterior a la v63: la misma fila, sin la columna.
    final filas = [for (final f in await cambiosDesde(pc, tabla: _tabla, desde: 0)) Map<String, dynamic>.from(f)..remove('rubro')];
    expect(await aplicarCambios(celular, tabla: _tabla, filas: filas), isEmpty);
    final config = await configuracionNegocioActual(celular);
    expect(config.nombreComercio, 'Almacén Ana');
    expect(config.rubro, 'almacen');
  });

  test('una configuración vieja que llega tarde no pisa la más nueva', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    final celular = await _celularConConfiguracionPropia();
    addTearDown(pc.close);
    addTearDown(celular.close);
    final vieja = await cambiosDesde(pc, tabla: _tabla, desde: 0); // la sembrada, época 0

    await aplicarCambios(celular, tabla: _tabla, filas: vieja);
    expect((await configuracionNegocioActual(celular)).nombreComercio, 'Kiosco Ana');
  });

  test('una base v49 con dos filas de configuración sube a v50 con una sola, la más reciente', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v50_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.configuracionNegocioTabla).get(); // drift crea la base recién con la primera consulta
    await nueva.close();

    // Como quedaba un equipo después del bug: la propia sin identidad y otra que llegó por la sync.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute("UPDATE configuracion_negocio_tabla SET global_id = NULL, actualizado_en = 0, nombre_comercio = 'vieja'");
      crudo.execute(
        "INSERT INTO configuracion_negocio_tabla (global_id, nombre_comercio, actualizado_en) VALUES ('otra', 'nueva', 2000000000)",
      );
      crudo.execute('PRAGMA user_version = 49');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(db.close);
    final filas = await db.select(db.configuracionNegocioTabla).get();
    expect(filas, hasLength(1));
    expect(filas.single.nombreComercio, 'nueva');
  });

  test('v50 le da el id fijo a la fila sin identidad de una PC instalada de cero', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v50b_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.configuracionNegocioTabla).get(); // drift crea la base recién con la primera consulta
    await nueva.close();
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('UPDATE configuracion_negocio_tabla SET global_id = NULL');
      crudo.execute('PRAGMA user_version = 49');
    } finally {
      crudo.close();
    }
    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(db.close);
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).globalId, globalIdConfiguracionNegocio);
  });
}
