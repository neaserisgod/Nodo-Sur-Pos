// Prueba de upgrade REAL (v30 → v31, backfill histórico para poder migrar
// TODAS las filas viejas a Firebase — El dueño, 2026-09-18) contra un archivo
// de verdad, no `NativeDatabase.memory()` — mismo motivo que
// `migracion_v30_test.dart`: en memoria siempre se pasa por `onCreate`
// (esquema más nuevo de una), nunca se ejercita `onUpgrade`.
//
// El esquema de v30 y v31 es IDÉNTICO — solo cambian los datos de filas que
// ya tenían `global_id = NULL` — así que para ESAS tablas no hace falta
// "arrancarle" columnas a mano al archivo: alcanza con crear los datos con
// `global_id` implícito (NULL, el default). Sí hace falta arrancarle a
// `usuarios` sus tres columnas de sync (agregadas recién en v31→v32,
// `migracion_v32_test.dart`): abrir este archivo con el código actual corre
// las dos migraciones de yapa (no hay forma de aislarlas), y sin arrancar
// esas columnas antes de bajar `user_version` la migración v32 fallaría con
// "duplicate column" al encontrarlas ya puestas por el `onCreate` inicial de
// este mismo test (que usa el esquema más nuevo, no el de v30).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import '../helpers/base_para_tests.dart';

void main() {
  test(
    'una base v30 real, al abrirse con el código actual, sube a v31 y le pone '
    'global_id a las filas viejas usando la fecha real de cada una',
    () async {
      final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v31_');
      final archivo = File('${carpeta.path}/base.sqlite');
      addTearDown(() => carpeta.delete(recursive: true));

      var db = AppDatabase(NativeDatabase(archivo), sembrarCatalogoDeTest);

      // `_seedDatosFijos` (onCreate) ya deja usuario, cajas, medios de pago y
      // ~11 categorías con `global_id` NULL — igual que la base real de
      // El dueño hoy. Se reusa ese usuario y esos medios en vez de sembrar de
      // nuevo.
      const usuarioId = 1;
      final medioEfectivo = await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(true))).getSingle();

      final proveedorId = await db.into(db.proveedores).insert(
        ProveedoresCompanion.insert(codigo: 'ZZ', nombre: 'Proveedor de prueba'),
      );

      final fechaProducto = DateTime(2026, 1, 10, 9, 0);
      final productoId = await db.into(db.productos).insert(
        ProductosCompanion.insert(
          nombre: 'Producto viejo',
          precioCentavos: const Value(100000),
          stock: const Value(5),
          creadoEn: Value(fechaProducto),
        ),
      );

      final fechaSesion = DateTime(2026, 1, 11, 8, 0);
      final sesionId = await db.into(db.sesionesDeCaja).insert(
        SesionesDeCajaCompanion.insert(
          usuarioAbrioId: usuarioId,
          fondoInicialCentavos: 0,
          fechaApertura: Value(fechaSesion),
        ),
      );

      final fechaVenta = DateTime(2026, 1, 12, 15, 30);
      final ventaId = await db.into(db.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          subtotalCentavos: 100000,
          totalCentavos: 100000,
          fecha: Value(fechaVenta),
        ),
      );

      final lineaId = await db.into(db.lineasDeVenta).insert(
        LineasDeVentaCompanion.insert(
          ventaId: ventaId,
          nombreProductoFoto: 'Producto viejo',
          precioUnitarioCentavos: 100000,
        ),
      );

      final pagoId = await db.into(db.pagos).insert(
        PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivo.id, montoCentavos: 100000),
      );

      final fechaPendiente = DateTime(2026, 1, 13, 10, 0);
      final pendienteId = await db.into(db.pendientes).insert(
        PendientesCompanion.insert(
          tipo: 'FIADO',
          usuarioId: usuarioId,
          montoCentavos: const Value(50000),
          fechaCreacion: Value(fechaPendiente),
        ),
      );

      final movimientoStockId = await db.into(db.movimientosDeStock).insert(
        MovimientosDeStockCompanion.insert(productoId: productoId, usuarioId: usuarioId, tipo: 'VENTA'),
      );

      final movimientoCajaId = await db.into(db.movimientosDeCaja).insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionId,
          cajaId: 1,
          usuarioId: usuarioId,
          tipo: 'VENTA',
          montoCentavos: 100000,
        ),
      );

      final arqueoId = await db.into(db.arqueosIntermedios).insert(
        ArqueosIntermediosCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          efectivoEsperadoCentavos: 0,
          diferenciaCentavos: 0,
          mpContadoCentavos: 0,
          mpEsperadoCentavos: 0,
          mpDiferenciaCentavos: 0,
          lataContadoCentavos: 0,
          lataEsperadoCentavos: 0,
          lataDiferenciaCentavos: 0,
        ),
      );

      final historialId = await db.into(db.historialDePrecios).insert(
        HistorialDePreciosCompanion.insert(productoId: productoId, usuarioId: usuarioId),
      );

      // Una categoría ya migrada de antes (simula una fila que YA pasó por
      // esto, ej. sincronizada desde el celular) — tiene que quedar
      // intacta, nunca pisada por el backfill.
      final categoriaYaMigradaId = await db.into(db.categorias).insert(
        CategoriasCompanion.insert(
          nombre: 'Ya migrada',
          globalId: const Value('ya-tenia-un-id'),
          origenDispositivo: const Value('android-x'),
          actualizadoEn: Value(DateTime(2026, 9, 1)),
        ),
      );

      await db.close();

      // Arrancamos a mano las tres columnas de sync de `usuarios` (mismo
      // mecanismo — `CREATE TABLE ... AS SELECT` de las columnas viejas,
      // vía `PRAGMA table_info` — que usa `migracion_v30_test.dart` para el
      // resto de las tablas) y bajamos `user_version` a 30: el esquema de
      // v30 y v31 es idéntico salvo por esto, solo hace falta que drift crea
      // que todavía no corrió ninguna de las dos migraciones.
      final crudo = sqlite3.sqlite3.open(archivo.path);
      try {
        crudo.execute('PRAGMA foreign_keys = OFF');
        const columnasNuevasUsuarios = {'global_id', 'origen_dispositivo', 'actualizado_en'};
        final infoColumnas = crudo.select('PRAGMA table_info(usuarios)');
        final columnasViejas = infoColumnas
            .map((fila) => fila['name'] as String)
            .where((nombre) => !columnasNuevasUsuarios.contains(nombre))
            .join(', ');
        crudo.execute('CREATE TABLE usuarios_v30 AS SELECT $columnasViejas FROM usuarios');
        crudo.execute('DROP TABLE usuarios');
        crudo.execute('ALTER TABLE usuarios_v30 RENAME TO usuarios');
        crudo.execute('PRAGMA user_version = 30');
      } finally {
        crudo.close();
      }

      // Reabrimos con el código real — `onUpgrade(from: 30, to: 32)` corre
      // (v30→v31, lo que prueba este archivo, y de yapa v31→v32, que
      // recompone las columnas de `usuarios` que se arrancaron arriba).
      db = AppDatabase(NativeDatabase(archivo));
      addTearDown(() => db.close());

      final categoriaVieja = await (db.select(
        db.categorias,
      )..where((c) => c.nombre.equals('Almacén'))).getSingle();
      expect(categoriaVieja.globalId, isNotNull);
      expect(categoriaVieja.globalId, hasLength(32));
      expect(categoriaVieja.origenDispositivo, 'desktop');
      // Sin fecha propia: época 0, a propósito (ver el comentario de la
      // migración en `database.dart`).
      expect(categoriaVieja.actualizadoEn, DateTime.fromMillisecondsSinceEpoch(0));

      final categoriaYaMigrada = await (db.select(
        db.categorias,
      )..where((c) => c.id.equals(categoriaYaMigradaId))).getSingle();
      expect(categoriaYaMigrada.globalId, 'ya-tenia-un-id'); // nunca se pisa
      expect(categoriaYaMigrada.origenDispositivo, 'android-x');
      expect(categoriaYaMigrada.actualizadoEn, DateTime(2026, 9, 1));

      final proveedor = await (db.select(
        db.proveedores,
      )..where((p) => p.id.equals(proveedorId))).getSingle();
      expect(proveedor.globalId, isNotNull);
      expect(proveedor.actualizadoEn, DateTime.fromMillisecondsSinceEpoch(0));

      final producto = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(productoId))).getSingle();
      expect(producto.globalId, isNotNull);
      expect(producto.origenDispositivo, 'desktop');
      expect(producto.actualizadoEn, fechaProducto);

      final sesion = await (db.select(
        db.sesionesDeCaja,
      )..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.globalId, isNotNull);
      expect(sesion.actualizadoEn, fechaSesion);

      final venta = await (db.select(
        db.ventas,
      )..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.globalId, isNotNull);
      expect(venta.actualizadoEn, fechaVenta);

      final linea = await (db.select(
        db.lineasDeVenta,
      )..where((l) => l.id.equals(lineaId))).getSingle();
      expect(linea.globalId, isNotNull);
      // Sin fecha propia: toma la de su venta.
      expect(linea.actualizadoEn, fechaVenta);

      final pago = await (db.select(
        db.pagos,
      )..where((p) => p.id.equals(pagoId))).getSingle();
      expect(pago.globalId, isNotNull);
      expect(pago.actualizadoEn, fechaVenta);

      final pendiente = await (db.select(
        db.pendientes,
      )..where((p) => p.id.equals(pendienteId))).getSingle();
      expect(pendiente.globalId, isNotNull);
      expect(pendiente.actualizadoEn, fechaPendiente);

      // Logs de solo-inserción: alcanza con la identidad, no tienen
      // `actualizado_en`.
      final movStock = await (db.select(
        db.movimientosDeStock,
      )..where((m) => m.id.equals(movimientoStockId))).getSingle();
      expect(movStock.globalId, isNotNull);
      expect(movStock.origenDispositivo, 'desktop');

      final movCaja = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.id.equals(movimientoCajaId))).getSingle();
      expect(movCaja.globalId, isNotNull);

      final arqueo = await (db.select(
        db.arqueosIntermedios,
      )..where((a) => a.id.equals(arqueoId))).getSingle();
      expect(arqueo.globalId, isNotNull);

      final historial = await (db.select(
        db.historialDePrecios,
      )..where((h) => h.id.equals(historialId))).getSingle();
      expect(historial.globalId, isNotNull);

      // Ningún `global_id` se repite entre sí (colisión = bug real, no solo
      // teórico: pasaría si todas las filas backfilleadas terminaran con el
      // mismo valor por error de interpolación de SQL).
      final todosLosIds = [
        categoriaVieja.globalId,
        proveedor.globalId,
        producto.globalId,
        sesion.globalId,
        venta.globalId,
        linea.globalId,
        pago.globalId,
        pendiente.globalId,
        movStock.globalId,
        movCaja.globalId,
        arqueo.globalId,
        historial.globalId,
      ];
      expect(todosLosIds.toSet().length, todosLosIds.length);
    },
  );
}
