// Prueba de upgrade REAL (v29 → v30, identidad de sincronización para la
// companion Android sin depender del escritorio) contra un archivo de
// verdad, no contra `NativeDatabase.memory()` — ver el comentario de
// `database_test.dart` sobre por qué el resto de los tests de este repo
// nunca ejercitan `onUpgrade`: todos abren en memoria, que siempre pasa por
// `onCreate` (crea el esquema entero de una, en la versión más nueva) sin
// importar qué migraciones existan.
//
// Acá se simula una base v29 real: se crea un archivo con el esquema actual
// (que ya incluye las columnas de la migración v30), se le arrancan esas
// columnas a mano con SQL crudo y se le marca `PRAGMA user_version = 29`, y
// recién ahí se reabre con el código real de la app — forzando que
// `onUpgrade` corra de verdad, incluido el loop que congela
// `stockBaseSincronizacion` producto por producto.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/base_para_tests.dart';

void main() {
  test(
    'una base v29 real, al abrirse con el código actual, sube a v30 sin '
    'perder datos y congela el stock existente como base de sincronización',
    () async {
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v30_');
      final archivo = File('${carpeta.path}/base.sqlite');
      addTearDown(() => carpeta.delete(recursive: true));

      // 1) Base "nueva" de verdad (onCreate ya deja el esquema v30 completo,
      // con las columnas de esta migración de fábrica) — se usa solo para
      // tener un archivo con datos reales y realistas para el paso 2.
      var db = AppDatabase(NativeDatabase(archivo), sembrarCatalogoDeTest);
      final productoId = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola 500ml',
              precioCentavos: const Value(112000),
              stock: const Value(37),
            ),
          );
      final proveedoresAntes = await db.select(db.proveedores).get();
      await db.close();

      // 2) Le "arrancamos" a mano las columnas de la migración v30 y
      // bajamos `user_version` a 29 — deja el archivo en el estado real que
      // tendría la base de Bruno HOY, antes de este cambio. `global_id` es
      // `UNIQUE`, y SQLite no deja hacer `DROP COLUMN` sobre una columna con
      // esa restricción (el índice implícito no se puede soltar aparte) —
      // por eso cada tabla se recrea entera con `CREATE TABLE ... AS
      // SELECT` de sus columnas viejas (leídas con `PRAGMA table_info`, no
      // transcriptas a mano, para no arriesgar un typo que invalide la
      // simulación) en vez de un `ALTER TABLE ... DROP COLUMN` por columna.
      final crudo = sqlite3.sqlite3.open(archivo.path);
      const columnasV30 = {
        'categorias': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'proveedores': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'clientes': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'productos': [
          'global_id',
          'origen_dispositivo',
          'stock_base_sincronizacion',
          'stock_gramos_base_sincronizacion',
          'stock_base_sincronizacion_fecha',
        ],
        'sesiones_de_caja': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'ventas': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'lineas_de_venta': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'pagos': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'movimientos_de_stock': ['global_id', 'origen_dispositivo'],
        'movimientos_de_caja': ['global_id', 'origen_dispositivo'],
        'arqueos_intermedios': ['global_id', 'origen_dispositivo'],
        'pendientes': ['global_id', 'origen_dispositivo', 'actualizado_en'],
        'historial_de_precios': ['global_id', 'origen_dispositivo'],
        'configuracion_tabla': ['dispositivo_apertura_designado_id'],
        // De la migración v31→v32 (`usuarios` se suma a la sincronización,
        // 2026-09-18) — va acá abajo con el resto, no en un mapa aparte: el
        // mecanismo de "arrancar columnas nuevas para simular una base
        // vieja" es el mismo sin importar en qué migración se agregaron.
        'usuarios': ['global_id', 'origen_dispositivo', 'actualizado_en'],
      };
      try {
        crudo.execute('PRAGMA foreign_keys = OFF'); // recrear tablas con FKs cruzadas
        for (final entrada in columnasV30.entries) {
          final tabla = entrada.key;
          final columnasNuevas = entrada.value.toSet();
          final infoColumnas = crudo.select('PRAGMA table_info($tabla)');
          final columnasViejas = infoColumnas
              .map((fila) => fila['name'] as String)
              .where((nombre) => !columnasNuevas.contains(nombre))
              .join(', ');
          crudo.execute('CREATE TABLE ${tabla}_v29 AS SELECT $columnasViejas FROM $tabla');
          crudo.execute('DROP TABLE $tabla');
          crudo.execute('ALTER TABLE ${tabla}_v29 RENAME TO $tabla');
        }
        crudo.execute('PRAGMA user_version = 29');
      } finally {
        // Siempre liberar el archivo, incluso si algo de arriba falla —
        // Windows no deja borrar un archivo con un handle todavía abierto,
        // y sin esto un fallo acá dejaría un segundo error de limpieza
        // tapando el error real en el resultado del test.
        crudo.close();
      }

      // 3) Reabrimos con el código real de la app — schemaVersion (hoy 32)
      // es mayor que lo que el archivo dice tener (29), así que drift llama
      // a `onUpgrade(from: 29, to: 32)` de verdad: corre el paso v29→v30 que
      // este test prueba, Y de yapa el backfill histórico de v30→v31
      // (`migracion_v31_test.dart`) y el de `usuarios` de v31→v32
      // (`migracion_v32_test.dart`) — no hay forma de aislar uno del otro
      // abriendo una base real, así que las aserciones de abajo asumen los
      // tres.
      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      // No perdió nada de lo que ya tenía.
      final proveedoresDespues = await db.select(db.proveedores).get();
      expect(proveedoresDespues.length, proveedoresAntes.length);

      final producto = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(productoId))).getSingle();
      expect(producto.nombre, 'Coca-Cola 500ml');
      expect(producto.stock, 37); // el stock en sí no se tocó

      // La columna nueva existe y es consultable, y quedó congelada al
      // valor real que tenía el producto en el momento de migrar (no en 0,
      // no null) — es la prueba de que el UPDATE por fila de la migración
      // corrió de verdad, no solo que la columna existe.
      expect(producto.stockBaseSincronizacion, 37);
      expect(producto.stockBaseSincronizacionFecha, isNotNull);

      // Identidad de sincronización: v30 la deja en NULL a propósito para
      // una fila que ya existía (ver su comentario en `database.dart` — no
      // se inventa un id para algo que nunca necesitó sincronizarse). Pero
      // el backfill de v30→v31 (`migracion_v31_test.dart`, agregado
      // 2026-09-18 para poder migrar el historial real a Firebase) corre en
      // la misma apertura y sí se lo pone — por eso acá se espera
      // `isNotNull`, no `isNull`.
      expect(producto.globalId, isNotNull);

      final unProveedorCualquiera = proveedoresDespues.first;
      expect(unProveedorCualquiera.globalId, isNotNull);

      final config = await db.select(db.configuracionTabla).getSingle();
      expect(config.dispositivoAperturaDesignadoId, isNull);
    },
  );
}
