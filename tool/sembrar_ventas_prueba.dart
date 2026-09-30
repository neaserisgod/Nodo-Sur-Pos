// Siembra una venta de prueba con productos de proveedores reales (no
// cigarrillos), directo en la base real de la app, para poder probar
// "Revisar ganancias" (Regla 13) sin esperar ventas reales — esa pantalla
// solo muestra proveedores con algo vendido desde la última revisión.
//
// Hace falta una sesión de caja ABIERTA (se siembra ahí adentro, con la
// fecha de ahora) — si no hay ninguna, no hace nada.
//
// Usa `package:sqlite3` puro, mismo motivo que `sembrar_productos_prueba.dart`:
// `package:la_plazoleta/data/database.dart` arrastra `drift_flutter` →
// `path_provider` → `dart:ui`, que no existe bajo `dart run`.
//
// Uso: dart run tool/sembrar_ventas_prueba.dart
// Cerrá la app antes de correrlo (si sqlite3.dll ya la tiene abierta, mejor
// no escribirle al mismo tiempo).
//
// NO es idempotente a propósito: cada corrida agrega una venta nueva (así se
// puede simular más de un "período" para revisar). Los productos que crea sí
// son idempotentes por nombre — no duplica "PRUEBA — X" si ya existe, así
// que correrlo varias veces no ensucia el catálogo, solo agrega ventas.
// Todo lo que crea lleva el prefijo "PRUEBA — " en el nombre del producto,
// para poder encontrarlo y borrarlo fácil (`DELETE FROM productos WHERE
// nombre LIKE 'PRUEBA — %'` deja las ventas ya generadas — para borrar todo
// de punta a punta hay que borrar también esas ventas/líneas/movimientos).

// ignore_for_file: avoid_print — es un script de línea de comandos, el
// feedback al usuario ES el print.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final perfil = Platform.environment['USERPROFILE'];
  if (perfil == null) {
    stderr.writeln('No se encontró USERPROFILE.');
    exit(1);
  }
  final ruta = '$perfil\\Documents\\la_plazoleta.sqlite';
  if (!File(ruta).existsSync()) {
    stderr.writeln('No existe $ruta — abrí la app al menos una vez antes de correr esto.');
    exit(1);
  }

  final db = sqlite3.open(ruta);
  final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final sesionAbierta = db.select("SELECT id FROM sesiones_de_caja WHERE estado = 'ABIERTA' LIMIT 1");
  if (sesionAbierta.isEmpty) {
    stderr.writeln('No hay ninguna sesión de caja ABIERTA — abrí caja en la app antes de correr esto.');
    db.close();
    exit(1);
  }
  final sesionId = sesionAbierta.first['id'] as int;
  final usuarioId = db.select('SELECT id FROM usuarios LIMIT 1').first['id'] as int;

  int productoIdPara({
    required String nombre,
    required String proveedorCodigo,
    required int costoCentavos,
    required int precioCentavos,
  }) {
    final existente = db.select('SELECT id FROM productos WHERE nombre = ?', [nombre]);
    if (existente.isNotEmpty) return existente.first['id'] as int;

    final proveedorId = db.select('SELECT id FROM proveedores WHERE codigo = ?', [proveedorCodigo]).first['id'] as int;
    db.execute(
      '''
      INSERT INTO productos
        (nombre, proveedor_id, es_varios, tipo_cigarrillo, es_pesable,
         precio_centavos, costo_centavos, stock, stock_minimo, activo, creado_en, actualizado_en)
      VALUES (?, ?, 0, 'ninguno', 0, ?, ?, 100, 0, 1, ?, ?)
      ''',
      [nombre, proveedorId, precioCentavos, costoCentavos, ahora, ahora],
    );
    return db.lastInsertRowId;
  }

  db.execute('BEGIN');
  try {
    // nombre, proveedor, costo, precio, cantidad — tres proveedores reales
    // distintos, ninguno cigarrillos (Distribuidora de Cigarrillos queda afuera de
    // "Revisar ganancias" a propósito, Regla 6).
    const items = [
      ('PRUEBA — Fiambre Fiambrería', 'F', 300000, 550000, 5),
      ('PRUEBA — Coca-Cola 2.25L', 'C', 120000, 180000, 8),
      ('PRUEBA — Cerveza Imperial 1L', 'W', 90000, 150000, 6),
    ];

    var subtotal = 0;
    final lineas = <({int productoId, int proveedorId, int costo, int precio, int cantidad})>[];
    for (final (nombre, codigo, costo, precio, cantidad) in items) {
      final productoId = productoIdPara(
        nombre: nombre,
        proveedorCodigo: codigo,
        costoCentavos: costo,
        precioCentavos: precio,
      );
      final proveedorId = db.select('SELECT id FROM proveedores WHERE codigo = ?', [codigo]).first['id'] as int;
      lineas.add((productoId: productoId, proveedorId: proveedorId, costo: costo, precio: precio, cantidad: cantidad));
      subtotal += precio * cantidad;
    }

    db.execute(
      'INSERT INTO ventas (sesion_caja_id, usuario_id, fecha, subtotal_centavos, total_centavos) VALUES (?, ?, ?, ?, ?)',
      [sesionId, usuarioId, ahora, subtotal, subtotal],
    );
    final ventaId = db.lastInsertRowId;

    db.execute('INSERT INTO pagos (venta_id, medio_pago_id, monto_centavos) VALUES (?, 1, ?)', [ventaId, subtotal]);

    db.execute(
      '''
      INSERT INTO movimientos_de_caja
        (sesion_caja_id, caja_id, venta_id, medio_pago_id, usuario_id, tipo, monto_centavos, fecha)
      VALUES (?, 1, ?, 1, ?, 'VENTA', ?, ?)
      ''',
      [sesionId, ventaId, usuarioId, subtotal, ahora],
    );

    for (final l in lineas) {
      final nombre = db.select('SELECT nombre FROM productos WHERE id = ?', [l.productoId]).first['nombre'];
      final stockActual = db.select('SELECT stock FROM productos WHERE id = ?', [l.productoId]).first['stock'] as int;

      db.execute(
        '''
        INSERT INTO lineas_de_venta
          (venta_id, producto_id, nombre_producto_foto, proveedor_id_foto, es_varios,
           tipo_cigarrillo, es_pesable, cantidad, precio_unitario_centavos, costo_unitario_centavos)
        VALUES (?, ?, ?, ?, 0, 'ninguno', 0, ?, ?, ?)
        ''',
        [ventaId, l.productoId, nombre, l.proveedorId, l.cantidad, l.precio, l.costo],
      );

      final stockPosterior = stockActual - l.cantidad;
      db.execute(
        '''
        INSERT INTO movimientos_de_stock
          (producto_id, venta_id, usuario_id, tipo, cantidad, stock_anterior, stock_posterior, fecha)
        VALUES (?, ?, ?, 'VENTA', ?, ?, ?, ?)
        ''',
        [l.productoId, ventaId, usuarioId, -l.cantidad, stockActual, stockPosterior, ahora],
      );
      db.execute('UPDATE productos SET stock = ?, actualizado_en = ? WHERE id = ?', [stockPosterior, ahora, l.productoId]);
    }

    db.execute('COMMIT');
    print('Sembrado OK: venta #$ventaId en sesión $sesionId, subtotal/total = $subtotal centavos.');
    print('Proveedores con ganancia pendiente ahora: Fiambrería, Coca Cola, Golosinas Oeste.');
  } catch (e) {
    db.execute('ROLLBACK');
    stderr.writeln('Error, no se sembró nada: $e');
    rethrow;
  } finally {
    db.close();
  }
}
