// Prueba de upgrade REAL (v43 → v44: nombre del comercio, encabezado del
// ticket y módulos desactivados en `configuracion_negocio_tabla`, fase 1 de
// la generalización del producto) contra un archivo de verdad, mismo motivo
// que `migracion_v34_test.dart`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('una base v43 real sube a v44: las tres columnas nuevas nacen vacías y nada de lo anterior cambia', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v44_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.configuracionNegocioTabla).get(); // abre la base: corre onCreate
    await nueva.close();

    // La base como estaba antes de este cambio: sin las tres columnas, con
    // valores de negocio distintos de los de fábrica (prueba que se conservan)
    // y con una fecha de modificación conocida (prueba que la migración no la
    // toca: si la tocara, cada dispositivo reenviaría la fila por sync).
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN nombre_comercio');
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN encabezado_ticket');
      crudo.execute('ALTER TABLE configuracion_negocio_tabla DROP COLUMN modulos_desactivados');
      crudo.execute(
        'UPDATE configuracion_negocio_tabla SET recargo_primer_atado_centavos = 41000, '
        'recargo_atado_adicional_centavos = 11000, recargo_suelto_centavos = 6000, '
        'paso_redondeo_centavos = 5000, actualizado_en = 1234',
      );
      crudo.execute('PRAGMA user_version = 43');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    final fila = await db.select(db.configuracionNegocioTabla).getSingle();
    expect(fila.nombreComercio, '');
    expect(fila.encabezadoTicket, '');
    expect(fila.modulosDesactivados, '');
    expect(fila.recargoPrimerAtadoCentavos, 41000);
    expect(fila.recargoAtadoAdicionalCentavos, 11000);
    expect(fila.recargoSueltoCentavos, 6000);
    expect(fila.pasoRedondeoCentavos, 5000);
    expect(fila.actualizadoEn!.millisecondsSinceEpoch, 1234 * 1000);
    expect((await modulosNegocioActuales(db)).desactivados, isEmpty);
  });

  test('subir dos veces a v44 (columnas ya presentes) no falla', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v44b_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await nueva.select(nueva.configuracionNegocioTabla).get();
    await nueva.close();

    // Solo se baja el número de versión: las columnas ya existen.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('PRAGMA user_version = 43');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    // Las columnas ya estaban: la migración no toca lo guardado (una base nueva trae el comparador apagado).
    expect((await db.select(db.configuracionNegocioTabla).getSingle()).modulosDesactivados, 'comparar_precios');
  });
}
