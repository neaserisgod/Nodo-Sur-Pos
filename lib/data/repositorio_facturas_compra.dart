// Aplicar y deshacer una factura de compra revisada (El dueño, 2026-10-07). Qué se aplica a cada producto lo decide
// `domain/aplicar_factura.dart`; acá se escribe todo junto, en una transacción, reusando los caminos de siempre para que deje el mismo
// rastro: `cargarDeuda` (cuenta corriente), `cargarCostoProducto` (historial de precios y precio automático del proveedor) y
// `ajustarStockRapido` (movimiento de stock, que es lo que viaja al celular).

import 'package:drift/drift.dart';

import '../domain/aplicar_factura.dart';
import 'database.dart';
import 'repositorio_deuda_proveedores.dart';
import 'repositorio_productos.dart';

/// Esa factura de ese proveedor ya se aplicó (y no se deshizo).
class FacturaYaCargadaException implements Exception {
  const FacturaYaCargadaException(this.aplicadaEn);
  final DateTime aplicadaEn;

  @override
  String toString() => 'Esta factura ya se cargó el ${aplicadaEn.day}/${aplicadaEn.month}/${aplicadaEn.year}.';
}

class ResultadoAplicarFactura {
  const ResultadoAplicarFactura({required this.facturaId, required this.productos, required this.pesablesSinTocar});
  final int facturaId;

  /// Cuántos productos cambiaron (stock o costo).
  final int productos;

  /// Productos por peso: la factura cuenta unidades y el stock de estos va en gramos, así que no se tocan (se cargan a mano).
  final List<String> pesablesSinTocar;
}

String _nota(String? numero) => 'Factura ${numero == null || numero.trim().isEmpty ? 'sin número' : numero.trim()}';

/// Aplica la factura: carga [lineas] en la cuenta corriente de [proveedorId] (el total impreso o, sin él, la suma), pone el costo de
/// cada producto (con el precio automático del proveedor si lo sigue) y, con [sumarStock], suma las unidades. Lanza
/// [FacturaYaCargadaException] si esa factura ya se aplicó, o [ArgumentError] si falta algo (`motivosParaNoAplicar`).
Future<ResultadoAplicarFactura> aplicarFactura(
  AppDatabase db, {
  required int? proveedorId,
  String? numero,
  String? tipo,
  DateTime? fecha,
  String? condicionPago,
  required int? totalImpresoCentavos,
  required List<LineaParaAplicar> lineas,
  required bool sumarStock,
  required int usuarioId,
}) {
  final motivos = motivosParaNoAplicar(proveedorId: proveedorId, tipo: tipo, lineas: lineas);
  if (motivos.isNotEmpty) throw ArgumentError(motivos.first);
  final proveedor = proveedorId!;
  return db.transaction(() async {
    final normalizado = numeroDeFacturaNormalizado(numero);
    if (normalizado != null) {
      final previa = await (db.select(db.facturasCompra)
            ..where((f) => f.proveedorId.equals(proveedor) & f.numeroNormalizado.equals(normalizado) & f.deshechaEn.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (previa != null) throw FacturaYaCargadaException(previa.aplicadaEn);
    }

    final total = montoDeLaDeuda(totalImpresoCentavos: totalImpresoCentavos, lineas: lineas);
    final nota = _nota(numero);
    final ahora = DateTime.now();
    final movimientoDeudaId = await cargarDeuda(db, proveedorId: proveedor, montoCentavos: total, fecha: fecha ?? ahora, nota: nota, usuarioId: usuarioId);
    final facturaId = await db.into(db.facturasCompra).insert(
          FacturasCompraCompanion.insert(
            proveedorId: proveedor,
            numero: Value(numero),
            numeroNormalizado: Value(normalizado),
            tipo: Value(tipo),
            fecha: Value(fecha),
            condicionPago: Value(condicionPago),
            totalCentavos: total,
            movimientoDeudaId: movimientoDeudaId,
            sumoStock: sumarStock,
            usuarioId: usuarioId,
            aplicadaEn: ahora,
          ),
        );

    final pesables = <String>[];
    var tocados = 0;
    for (final a in aplicacionesPorProducto(lineas)) {
      final p = await _producto(db, a.productoId);
      if (p.esPesable) {
        pesables.add(p.nombre);
        continue;
      }
      if (p.costoCentavos != a.costoUnitarioCentavos) {
        await cargarCostoProducto(db, productoId: p.id, costoCentavos: a.costoUnitarioCentavos, usuarioId: usuarioId);
      }
      if (sumarStock) {
        final actual = await _producto(db, a.productoId);
        await ajustarStockRapido(db, productoId: p.id, usuarioId: usuarioId, stock: actual.stock + a.unidades, stockGramos: actual.stockGramos, motivo: 'Compra · $nota');
      }
      await db.into(db.productosFacturaCompra).insert(
            ProductosFacturaCompraCompanion.insert(
              facturaId: facturaId,
              productoId: p.id,
              unidadesSumadas: sumarStock ? a.unidades : 0,
              costoAnteriorCentavos: Value(p.costoCentavos),
              costoNuevoCentavos: a.costoUnitarioCentavos,
            ),
          );
      tocados++;
    }
    return ResultadoAplicarFactura(facturaId: facturaId, productos: tocados, pesablesSinTocar: pesables);
  });
}

class ResultadoDeshacerFactura {
  const ResultadoDeshacerFactura({required this.costosQueQuedaron});

  /// Productos cuyo costo se cambió a mano después de la factura: ese costo no se pisa.
  final List<String> costosQueQuedaron;
}

/// Deshace [facturaId]: anula el cargo en la cuenta corriente, resta el stock que sumó y vuelve al costo de antes — salvo que el costo
/// se haya cambiado después (ese queda, y se avisa). Si ya hay un pago que depende del cargo, primero hay que anular ese pago.
Future<ResultadoDeshacerFactura> deshacerFactura(AppDatabase db, {required int facturaId, required int usuarioId}) {
  return db.transaction(() async {
    final f = await (db.select(db.facturasCompra)..where((t) => t.id.equals(facturaId))).getSingle();
    if (f.deshechaEn != null) throw ArgumentError('Esta factura ya estaba deshecha.');
    try {
      await anularMovimientoDeuda(db, movimientoId: f.movimientoDeudaId, usuarioId: usuarioId);
    } on ArgumentError {
      throw ArgumentError('Ya hay un pago a cuenta de esta factura: anulá primero ese pago en la cuenta corriente y después deshacela.');
    }

    final nota = _nota(f.numero);
    final quedaron = <String>[];
    final productos = await (db.select(db.productosFacturaCompra)..where((t) => t.facturaId.equals(facturaId))).get();
    for (final pf in productos) {
      var p = await _producto(db, pf.productoId);
      if (pf.unidadesSumadas > 0) {
        await ajustarStockRapido(db, productoId: p.id, usuarioId: usuarioId, stock: p.stock - pf.unidadesSumadas, stockGramos: p.stockGramos, motivo: 'Deshacer compra · $nota');
        p = await _producto(db, pf.productoId);
      }
      if (pf.costoAnteriorCentavos == pf.costoNuevoCentavos) continue;
      if (p.costoCentavos != pf.costoNuevoCentavos || pf.costoAnteriorCentavos == null) {
        quedaron.add(p.nombre);
        continue;
      }
      await cargarCostoProducto(db, productoId: p.id, costoCentavos: pf.costoAnteriorCentavos!, usuarioId: usuarioId);
    }
    await (db.update(db.facturasCompra)..where((t) => t.id.equals(facturaId))).write(FacturasCompraCompanion(deshechaEn: Value(DateTime.now())));
    return ResultadoDeshacerFactura(costosQueQuedaron: quedaron);
  });
}

/// La factura (sin deshacer) que cargó ese movimiento de la cuenta corriente, o null si el cargo se anotó a mano.
Future<FacturaCompraFila?> facturaDelMovimientoDeuda(AppDatabase db, int movimientoDeudaId) =>
    (db.select(db.facturasCompra)..where((f) => f.movimientoDeudaId.equals(movimientoDeudaId) & f.deshechaEn.isNull())).getSingleOrNull();

/// Los ids de los cargos de la cuenta corriente que vienen de una factura sin deshacer (para mostrarles "Deshacer factura").
Future<Set<int>> movimientosDeudaConFactura(AppDatabase db, int proveedorId) async {
  final filas = await (db.select(db.facturasCompra)..where((f) => f.proveedorId.equals(proveedorId) & f.deshechaEn.isNull())).get();
  return {for (final f in filas) f.movimientoDeudaId};
}

Future<Producto> _producto(AppDatabase db, int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
