// Encargues por apartado (El dueño, 2026-10-02): un cliente pide algo que YA está en el local y se lo aparta.
//
//  * Apartar saca el stock en el momento (movimiento AJUSTE con el motivo "Apartado para X", Regla 6): así lo que se
//    prometió no se le vende a otro. Si no alcanza el stock no se aparta nada.
//  * Cancelar lo devuelve, también con rastro, y solo una vez.
//  * Entregar es una venta normal (precios de hoy) que libera lo apartado EN LA MISMA TRANSACCIÓN que la venta
//    (`registrarVenta(encargueId:)`): la venta descuenta el stock de nuevo, así que sin devolver lo apartado se
//    descontaría dos veces. Si el cobro no se completa, nada de esto pasa y el encargue sigue apartado.
//
// Se guarda en `pendientes` (tipo 'ENCARGUE', ya sincronizada) con las líneas en JSON por `global_id` del producto.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_productos.dart';
import 'repositorio_ventas.dart' show lineaDesdeProducto;

/// Lo que se quiere apartar: un producto y, según sea, unidades o gramos.
class LineaEncargueNueva {
  const LineaEncargueNueva({required this.productoId, this.cantidad, this.gramos})
      : assert((cantidad == null) != (gramos == null), 'unidades o gramos, no los dos');
  final int productoId;
  final int? cantidad;
  final int? gramos;
}

/// Lo apartado, tal como queda guardado.
class LineaEncargue {
  const LineaEncargue({required this.productoGlobalId, required this.nombre, this.cantidad, this.gramos});
  final String productoGlobalId;
  final String nombre;
  final int? cantidad;
  final int? gramos;

  Map<String, dynamic> toJson() => {
        'gid': productoGlobalId,
        'nombre': nombre,
        if (cantidad != null) 'cantidad': cantidad,
        if (gramos != null) 'gramos': gramos,
      };

  factory LineaEncargue.desdeJson(Map<String, dynamic> j) => LineaEncargue(
        productoGlobalId: j['gid'] as String,
        nombre: j['nombre'] as String,
        cantidad: (j['cantidad'] as num?)?.toInt(),
        gramos: (j['gramos'] as num?)?.toInt(),
      );

  /// "3 × Galletitas" o "250 g Queso barra".
  String get texto => gramos != null ? '$gramos g $nombre' : '$cantidad × $nombre';
}

class Encargue {
  const Encargue({required this.id, required this.nombreCliente, required this.lineas, required this.desde});
  final int id;
  final String nombreCliente;
  final List<LineaEncargue> lineas;
  final DateTime desde;

  String get resumen => lineas.map((l) => l.texto).join(', ');
}

/// No alcanza el stock para apartar [nombreProducto].
class EncargueSinStock implements Exception {
  const EncargueSinStock(this.nombreProducto);
  final String nombreProducto;
  @override
  String toString() => 'No alcanza el stock de $nombreProducto para apartarlo.';
}

List<LineaEncargue> _leerLineas(String? json) {
  if (json == null || json.isEmpty) return const [];
  return [for (final j in jsonDecode(json) as List) LineaEncargue.desdeJson(Map<String, dynamic>.from(j as Map))];
}

/// Mueve el stock de [producto] en [delta] (unidades) o [deltaGramos] y deja el movimiento.
Future<void> _moverStock(
  AppDatabase db, {
  required Producto producto,
  required int usuarioId,
  int? delta,
  int? deltaGramos,
  required String motivo,
}) async {
  final nuevoStock = producto.stock + (delta ?? 0);
  final nuevosGramos = deltaGramos == null ? producto.stockGramos : (producto.stockGramos ?? 0) + deltaGramos;
  await (db.update(db.productos)..where((p) => p.id.equals(producto.id)))
      .write(ProductosCompanion(stock: Value(nuevoStock), stockGramos: Value(nuevosGramos)));
  await registrarAjusteDeStock(
    db,
    productoId: producto.id,
    usuarioId: usuarioId,
    anterior: producto,
    stock: nuevoStock,
    stockGramos: nuevosGramos,
    motivo: motivo,
  );
}

Future<Producto> _productoPorGlobalId(AppDatabase db, String gid) =>
    (db.select(db.productos)..where((p) => p.globalId.equals(gid))).getSingle();

/// Un producto sin identidad de sincronización (anterior a la sync, o cargado por un camino que no se la dio) la recibe
/// acá: el encargue se refiere a él por `global_id`. Se marca como cambiado para que suba con esa identidad.
Future<String> _darIdentidad(AppDatabase db, Producto producto) async {
  final gid = generarGlobalId();
  await (db.update(db.productos)..where((p) => p.id.equals(producto.id)))
      .write(ProductosCompanion(globalId: Value(gid), actualizadoEn: Value(DateTime.now())));
  return gid;
}

/// Aparta [lineas] para [nombreCliente]: baja el stock y deja el encargue pendiente. Todo o nada.
Future<int> crearEncargueApartando(
  AppDatabase db, {
  required String nombreCliente,
  required List<LineaEncargueNueva> lineas,
  required int usuarioId,
}) {
  final nombre = nombreCliente.trim();
  if (nombre.isEmpty) throw ArgumentError('El encargue necesita el nombre del cliente.');
  if (lineas.isEmpty) throw ArgumentError('El encargue necesita al menos un producto.');
  return db.transaction(() async {
    final guardadas = <LineaEncargue>[];
    for (final l in lineas) {
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(l.productoId))).getSingle();
      final gramos = l.gramos;
      final unidades = l.cantidad;
      if ((gramos ?? unidades ?? 0) <= 0) throw ArgumentError('La cantidad apartada tiene que ser mayor a cero.');
      final gid = producto.globalId ?? await _darIdentidad(db, producto);
      final alcanza = gramos != null ? (producto.stockGramos ?? 0) >= gramos : producto.stock >= unidades!;
      if (!alcanza) throw EncargueSinStock(producto.nombre);
      await _moverStock(
        db,
        producto: producto,
        usuarioId: usuarioId,
        delta: unidades == null ? null : -unidades,
        deltaGramos: gramos == null ? null : -gramos,
        motivo: 'Apartado para $nombre',
      );
      guardadas.add(LineaEncargue(productoGlobalId: gid, nombre: producto.nombre, cantidad: unidades, gramos: gramos));
    }
    return db.into(db.pendientes).insert(
          PendientesCompanion.insert(
            tipo: 'ENCARGUE',
            nombreLibre: Value(nombre),
            // El tablero y los encargues viejos leen `descripcion`: queda el resumen legible.
            descripcion: Value(guardadas.map((l) => l.texto).join(', ')),
            lineasJson: Value(jsonEncode([for (final l in guardadas) l.toJson()])),
            usuarioId: usuarioId,
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
  });
}

/// Los encargues por apartado todavía sin entregar, el más viejo primero.
Future<List<Encargue>> listarEnarguesPendientes(AppDatabase db) async {
  final filas = await (db.select(db.pendientes)
        ..where((p) => p.tipo.equals('ENCARGUE') & p.estado.equals('PENDIENTE') & p.lineasJson.isNotNull())
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion)]))
      .get();
  return [
    for (final p in filas)
      Encargue(id: p.id, nombreCliente: p.nombreLibre ?? '', lineas: _leerLineas(p.lineasJson), desde: p.fechaCreacion),
  ];
}

/// Devuelve al stock lo apartado por [pendiente] y deja el movimiento con [motivo].
Future<void> _devolverApartado(AppDatabase db, Pendiente pendiente, {required int usuarioId, required String motivo}) async {
  for (final l in _leerLineas(pendiente.lineasJson)) {
    final producto = await _productoPorGlobalId(db, l.productoGlobalId);
    await _moverStock(db, producto: producto, usuarioId: usuarioId, delta: l.cantidad, deltaGramos: l.gramos, motivo: motivo);
  }
}

/// Cancela un encargue pendiente y devuelve lo apartado. Si ya no está pendiente (ya se entregó o ya se canceló) no hace
/// nada: devolver stock dos veces, o stock que ya se vendió, lo inventaría.
Future<void> cancelarEncargue(AppDatabase db, int id, {required int usuarioId}) {
  return db.transaction(() async {
    final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (p == null || p.estado != 'PENDIENTE') return;
    await _devolverApartado(db, p, usuarioId: usuarioId, motivo: 'Encargue cancelado: ${p.nombreLibre}');
    await (db.update(db.pendientes)..where((x) => x.id.equals(id))).write(PendientesCompanion(
      estado: const Value('CANCELADO'),
      fechaResuelta: Value(DateTime.now()),
      actualizadoEn: Value(DateTime.now()),
    ));
  });
}

/// Las líneas de venta de lo apartado, a los precios de HOY (Regla 4: el precio es el del momento del cobro, no el de
/// cuando se apartó).
Future<List<LineaVenta>> lineasParaEntregar(AppDatabase db, int id) async {
  final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingle();
  final lineas = <LineaVenta>[];
  for (final l in _leerLineas(p.lineasJson)) {
    final producto = await _productoPorGlobalId(db, l.productoGlobalId);
    lineas.add(lineaDesdeProducto(producto, cantidad: l.cantidad, gramos: l.gramos));
  }
  return lineas;
}

/// Lo llama `registrarVenta` dentro de su transacción al cobrar la entrega: devuelve lo apartado (la venta lo descuenta
/// ella) y deja el encargue resuelto con la venta que lo saldó.
Future<void> liberarEncargueEntregado(AppDatabase db, int id, {required int ventaId, required int usuarioId}) async {
  final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingleOrNull();
  if (p == null || p.estado != 'PENDIENTE') return;
  await _devolverApartado(db, p, usuarioId: usuarioId, motivo: 'Encargue entregado: ${p.nombreLibre}');
  await (db.update(db.pendientes)..where((x) => x.id.equals(id))).write(PendientesCompanion(
    estado: const Value('RESUELTO'),
    ventaId: Value(ventaId),
    fechaResuelta: Value(DateTime.now()),
    actualizadoEn: Value(DateTime.now()),
  ));
}
