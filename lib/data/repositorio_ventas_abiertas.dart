// Ventas armadas y sin cobrar (tabla `ventas_abiertas`): las pestañas de la
// pantalla de venta. Ver el comentario de la tabla — es un borrador, no toca
// stock ni caja.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/venta.dart';
import '../domain/venta_json.dart';
import 'database.dart';

/// El estado de una venta armada, tal como se guarda y se restaura. Es lo
/// mínimo para que retomarla deje la pantalla como estaba: carrito, medio de
/// pago a medio elegir y descuento tipeado.
class BorradorVenta {
  const BorradorVenta({
    this.id,
    this.lineas = const [],
    this.medio,
    this.montoEfectivoMixtoCentavos,
    this.canal,
    this.tipoDescuento = 'monto',
    this.textoDescuento = '',
  });

  /// Null hasta que se guarda por primera vez (una pestaña vacía no ocupa
  /// una fila).
  final int? id;
  final List<LineaVenta> lineas;
  final String? medio;
  final int? montoEfectivoMixtoCentavos;
  final String? canal;
  final String tipoDescuento;
  final String textoDescuento;

  /// Vacía = nada que conservar: sin líneas ni descuento tipeado.
  bool get estaVacio => lineas.isEmpty && textoDescuento.trim().isEmpty;

  BorradorVenta conId(int? nuevoId) => BorradorVenta(
    id: nuevoId,
    lineas: lineas,
    medio: medio,
    montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
    canal: canal,
    tipoDescuento: tipoDescuento,
    textoDescuento: textoDescuento,
  );

  /// Clave de comparación: si no cambió, no hay nada que volver a escribir.
  String get firma => jsonEncode([
    for (final l in lineas) lineaVentaAJson(l),
    medio,
    montoEfectivoMixtoCentavos,
    canal,
    tipoDescuento,
    textoDescuento,
  ]);
}

BorradorVenta _desdeFila(VentaAbiertaFila fila) {
  final lineas = <LineaVenta>[
    for (final j in jsonDecode(fila.lineasJson) as List)
      lineaVentaDesdeJson(Map<String, dynamic>.from(j as Map)),
  ];
  return BorradorVenta(
    id: fila.id,
    lineas: lineas,
    medio: fila.medio,
    montoEfectivoMixtoCentavos: fila.montoEfectivoMixtoCentavos,
    canal: fila.canal,
    tipoDescuento: fila.tipoDescuento,
    textoDescuento: fila.textoDescuento,
  );
}

/// Las ventas abiertas de [sesionId], en el orden de las pestañas. Una fila
/// ilegible (JSON roto) se ignora en vez de trabar la pantalla de venta.
Future<List<BorradorVenta>> cargarVentasAbiertas(AppDatabase db, int sesionId) async {
  final filas =
      await (db.select(db.ventasAbiertas)
            ..where((v) => v.sesionCajaId.equals(sesionId))
            ..orderBy([(v) => OrderingTerm.asc(v.orden), (v) => OrderingTerm.asc(v.id)]))
          .get();
  final resultado = <BorradorVenta>[];
  for (final fila in filas) {
    try {
      resultado.add(_desdeFila(fila));
    } catch (_) {
      continue;
    }
  }
  return resultado;
}

/// Inserta o actualiza el borrador; devuelve su id.
Future<int> guardarVentaAbierta(
  AppDatabase db, {
  required int sesionId,
  required int orden,
  required BorradorVenta borrador,
}) async {
  final companion = VentasAbiertasCompanion(
    sesionCajaId: Value(sesionId),
    orden: Value(orden),
    lineasJson: Value(jsonEncode([for (final l in borrador.lineas) lineaVentaAJson(l)])),
    medio: Value(borrador.medio),
    montoEfectivoMixtoCentavos: Value(borrador.montoEfectivoMixtoCentavos),
    canal: Value(borrador.canal),
    tipoDescuento: Value(borrador.tipoDescuento),
    textoDescuento: Value(borrador.textoDescuento),
    actualizadoEn: Value(DateTime.now()),
  );
  final id = borrador.id;
  if (id == null) return db.into(db.ventasAbiertas).insert(companion);
  await (db.update(db.ventasAbiertas)..where((v) => v.id.equals(id))).write(companion);
  return id;
}

Future<void> borrarVentaAbierta(AppDatabase db, int id) =>
    (db.delete(db.ventasAbiertas)..where((v) => v.id.equals(id))).go();

/// Cuántas ventas abiertas con algo cargado tiene [sesionId] — lo que
/// bloquea el cierre de caja (El dueño, 2026-09-29).
Future<int> cantidadVentasAbiertasConLineas(AppDatabase db, int sesionId) async {
  final filas = await cargarVentasAbiertas(db, sesionId);
  return filas.where((b) => b.lineas.isNotEmpty).length;
}

/// Tira las ventas abiertas de [sesionId] (el "descartar" explícito del
/// cierre: sin esto, una sesión vencida que ya no deja vender quedaría
/// trabada para siempre por ventas que nadie puede cobrar).
Future<void> descartarVentasAbiertas(AppDatabase db, int sesionId) =>
    (db.delete(db.ventasAbiertas)..where((v) => v.sesionCajaId.equals(sesionId))).go();

/// Se tira desde `cerrarSesion` si quedan ventas abiertas con algo cargado.
class VentasAbiertasPendientesException implements Exception {
  const VentasAbiertasPendientesException(this.cantidad);
  final int cantidad;
}
