// Medición, no verificación: cuánto tardan las consultas que se abren a diario con un historial de dos años. Se corre a mano:
//   flutter test test/bench --tags bench
// y escribe los tiempos en la consola. Sirvió para decidir qué optimizar (Fase 0.14) y para ver que no empeore.
@Tags(['bench'])
library;

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_historial.dart';
import 'package:la_plazoleta/data/repositorio_historial_ventas.dart';
import 'package:la_plazoleta/data/repositorio_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_tablero.dart';
import 'package:la_plazoleta/domain/periodo.dart';

const _dias = 600;
const _ventasPorDia = 100;
const _lineasPorVenta = 3;

Future<AppDatabase> _baseConHistorial() async {
  final db = AppDatabase(NativeDatabase.memory());
  for (var i = 0; i < 15; i++) {
    await db.customStatement("INSERT INTO proveedores (codigo, nombre, global_id) VALUES ('P$i', 'Proveedor $i', 'prov$i')");
  }
  final proveedores = (await db.select(db.proveedores).get()).map((p) => p.id).toList();
  final usuario = (await db.select(db.usuarios).get()).first.id;
  final medios = (await db.select(db.mediosDePago).get());
  final efectivo = medios.firstWhere((m) => m.esEfectivo).id;
  final virtual = medios.firstWhere((m) => !m.esEfectivo).id;
  await db.transaction(() async {
    for (var p = 0; p < 300; p++) {
      await db.customStatement(
        "INSERT INTO productos (nombre, proveedor_id, precio_centavos, costo_centavos, stock, global_id) "
        "VALUES ('Producto $p', ${proveedores[p % proveedores.length]}, 100000, 60000, 50, 'p$p')",
      );
    }
    final hoy = DateTime.now();
    var ventaId = 0;
    for (var d = _dias; d >= 1; d--) {
      final dia = DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: d)).add(const Duration(hours: 10));
      await db.customInsert(
        'INSERT INTO sesiones_de_caja (fecha_apertura, fecha_cierre, usuario_abrio_id, fondo_inicial_centavos, estado, '
        'efectivo_esperado_centavos, efectivo_contado_centavos, diferencia_centavos, global_id) '
        "VALUES (?, ?, ?, 0, 'CERRADA', 0, 0, 0, ?)",
        variables: [Variable.withInt(dia.millisecondsSinceEpoch ~/ 1000), Variable.withInt(dia.add(const Duration(hours: 9)).millisecondsSinceEpoch ~/ 1000), Variable.withInt(usuario), Variable.withString('s$d')],
      );
      final sesion = (await db.customSelect('SELECT last_insert_rowid() AS id').getSingle()).read<int>('id');
      for (var v = 0; v < _ventasPorDia; v++) {
        ventaId++;
        final fecha = dia.add(Duration(minutes: v * 5)).millisecondsSinceEpoch ~/ 1000;
        await db.customInsert(
          'INSERT INTO ventas (sesion_caja_id, usuario_id, fecha, subtotal_centavos, total_centavos, global_id) VALUES (?, ?, ?, 300000, 300000, ?)',
          variables: [Variable.withInt(sesion), Variable.withInt(usuario), Variable.withInt(fecha), Variable.withString('v$ventaId')],
        );
        await db.customInsert('INSERT INTO pagos (venta_id, medio_pago_id, monto_centavos, global_id) VALUES (?, ?, 300000, ?)',
            variables: [Variable.withInt(ventaId), Variable.withInt(v.isEven ? efectivo : virtual), Variable.withString('g$ventaId')]);
        for (var l = 0; l < _lineasPorVenta; l++) {
          await db.customInsert(
            'INSERT INTO lineas_de_venta (venta_id, producto_id, nombre_producto_foto, proveedor_id_foto, cantidad, precio_unitario_centavos, costo_unitario_centavos, global_id) '
            "VALUES (?, ?, 'Producto', ?, 1, 100000, 60000, ?)",
            variables: [Variable.withInt(ventaId), Variable.withInt(1 + (ventaId + l) % 300), Variable.withInt(proveedores[(ventaId + l) % proveedores.length]), Variable.withString('l$ventaId-$l')],
          );
        }
      }
    }
  });
  return db;
}

Future<void> _medir(String nombre, Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    await f();
    // ignore: avoid_print
    print('BENCH ${nombre.padRight(46)} ${sw.elapsedMilliseconds} ms');
  } catch (e) {
    // ignore: avoid_print
    print('BENCH ${nombre.padRight(46)} FALLÓ tras ${sw.elapsedMilliseconds} ms: ${e.toString().split('\n').first}');
  }
}

void main() {
  test('tiempos con ${_dias * _ventasPorDia} ventas', timeout: const Timeout(Duration(minutes: 10)), () async {
    final db = await _baseConHistorial();
    addTearDown(db.close);
    final ahora = DateTime.now();
    

    Future<void> todas() async {
      await _medir('listarDias (cierres de caja)', () => listarDias(db));
      await _medir('tableroDelDia (Inicio)', () => tableroDelDia(db));
      await _medir('historialDeVentas (hoy)', () => historialDeVentas(db, desde: DateTime(ahora.year, ahora.month, ahora.day), hasta: ahora.add(const Duration(days: 1))));
      await _medir('historialDeVentas (este mes)', () => historialDeVentas(db, desde: DateTime(ahora.year, ahora.month, 1), hasta: ahora.add(const Duration(days: 1))));
      await _medir('resumenProveedoresNivel1 (mes)', () => resumenProveedoresNivel1(db, periodo: PeriodoResumen.mes, ahora: ahora));
      await _medir('resumenTodosLosProductos (mes)', () => resumenTodosLosProductos(db, periodo: PeriodoResumen.mes, ahora: ahora));
      await _medir('resumenReposicionDeProveedor', () async => resumenReposicionDeProveedor(db, (await db.select(db.proveedores).get()).first));
      await _medir('separacionesDelDia (Separaciones)', () => separacionesDelDia(db));
      await _medir('vendidoPorProductoDesde (30 días)', () => vendidoPorProductoDesde(db, ahora.subtract(const Duration(days: 30))));
    }

    // ignore: avoid_print
    print('BENCH --- proveedores NUNCA separados (todo el historial cuenta): el peor caso');
    await todas();

    // Lo normal en el local: se separa todos los días, así que el corte de cada proveedor es de ayer.
    final ayer = DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(hours: 4)).millisecondsSinceEpoch ~/ 1000;
    await db.customStatement('UPDATE proveedores SET corte_reposicion_fecha = $ayer, ganancia_revisada_fecha = $ayer');
    // ignore: avoid_print
    print('BENCH --- proveedores con corte de ayer: el caso de todos los días');
    await todas();
  });
}
