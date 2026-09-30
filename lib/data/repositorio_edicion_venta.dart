// Edición completa de una venta ya cobrada (fase 9, Regla 9): reabre el
// carrito, permite cambiar cualquier cosa (líneas, cantidades, medio de
// pago) y aplica la diferencia.
//
// El estado ACTUAL de la venta (`ventas`, `lineas_de_venta`, `pagos`) se
// sobrescribe con los valores nuevos — no tendría sentido mostrar "2 líneas
// viejas + 2 líneas nuevas" de la misma venta. El libro mayor
// (`movimientos_de_stock`, `movimientos_de_caja`) en cambio NUNCA se toca
// ni se borra (Regla 6, "todo movimiento deja rastro"): se le agrega una
// reversión de lo viejo y una reaplicación de lo nuevo, ambas fechadas al
// momento de la edición.
//
// La reversión de caja usa tipo 'VENTA' (no 'AJUSTE') a propósito, con
// monto negativo: `efectivoDeVentasDelDia` (repositorio_cierre.dart) suma
// por tipo, así que la reversión tiene que ser del mismo tipo para
// cancelar al original en ese cálculo. La reversión de stock sí es tipo
// 'AJUSTE': el stock actual se lee directo de `productos.stock`, nunca se
// deriva sumando movimientos, así que el tipo ahí es solo para auditoría.

import 'package:drift/drift.dart';

import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_ventas.dart';

const _motivoReversion = 'Reversión por edición de venta';
const _motivoReaplicacion = 'Reaplicación por edición de venta';
const _motivoReversionAnulacion = 'Reversión por anulación de venta';

/// Reconstruye la `LineaVenta` de dominio a partir de una fila ya
/// persistida — el conversor inverso de `lineaDesdeProducto` (esa parte de
/// un producto del catálogo; esta parte de lo que ya se guardó). Lo usa el
/// editor de venta para reabrir el carrito con lo que la venta ya tenía.
///
/// Una línea sin `productoId` (carga histórica: detalle libre, sin producto
/// real del catálogo) se reconstruye como si fuera "Varios": no hay stock
/// real que tocar de todos modos, y así el resto del motor de persistencia
/// no necesita un caso especial para esto.
LineaVenta lineaVentaDesdeFila(FilaLineaVenta fila, {required int productoVariosId}) {
  final sinProductoReal = fila.productoId == null;
  final productoId = sinProductoReal ? productoVariosId : fila.productoId!;

  if (fila.esPesable) {
    return LineaVentaPesable(
      productoId: productoId.toString(),
      nombreProducto: fila.nombreProductoFoto,
      proveedorId: fila.proveedorIdFoto?.toString(),
      gramos: fila.gramos!,
      precioPorKiloCentavos: fila.precioUnitarioCentavos,
      costoPorKiloCentavos: fila.costoUnitarioCentavos,
    );
  }

  return LineaVentaPorUnidad(
    productoId: productoId.toString(),
    nombreProducto: fila.nombreProductoFoto,
    proveedorId: fila.proveedorIdFoto?.toString(),
    cantidad: fila.cantidad ?? 1,
    esVarios: sinProductoReal || fila.esVarios,
    tipoCigarrillo: tipoCigarrilloDesde(fila.tipoCigarrillo),
    precioUnitarioCentavos: fila.precioUnitarioCentavos,
    costoUnitarioCentavos: fila.costoUnitarioCentavos,
  );
}

/// [motivo] distingue en `movimientos_de_stock` si esta reversión viene de
/// editar o de anular una venta — mismo mecanismo, dos orígenes.
Future<void> _revertirLinea(
  AppDatabase db, {
  required FilaLineaVenta linea,
  required int ventaId,
  required int usuarioId,
  required String motivo,
}) async {
  if (linea.esVarios || linea.productoId == null) return;
  final productoId = linea.productoId!;
  final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();

  if (linea.esPesable) {
    final anterior = producto.stockGramos ?? 0;
    final posterior = anterior + (linea.gramos ?? 0);
    await (db.update(db.productos)..where((p) => p.id.equals(productoId)))
        .write(ProductosCompanion(stockGramos: Value(posterior)));
    await db.into(db.movimientosDeStock).insert(
          MovimientosDeStockCompanion.insert(
            productoId: productoId,
            usuarioId: usuarioId,
            tipo: 'AJUSTE',
            ventaId: Value(ventaId),
            gramos: Value(linea.gramos),
            gramosAnterior: Value(anterior),
            gramosPosterior: Value(posterior),
            motivo: Value(motivo),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  } else {
    final anterior = producto.stock;
    final posterior = anterior + (linea.cantidad ?? 1);
    await (db.update(db.productos)..where((p) => p.id.equals(productoId)))
        .write(ProductosCompanion(stock: Value(posterior)));
    await db.into(db.movimientosDeStock).insert(
          MovimientosDeStockCompanion.insert(
            productoId: productoId,
            usuarioId: usuarioId,
            tipo: 'AJUSTE',
            ventaId: Value(ventaId),
            cantidad: Value(linea.cantidad),
            stockAnterior: Value(anterior),
            stockPosterior: Value(posterior),
            motivo: Value(motivo),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  }
}

Future<void> editarVenta(
  AppDatabase db, {
  required int ventaId,
  required Venta ventaNueva,
  required ResultadoTotalVenta resultadoNuevo,
  required List<PagoARegistrar> pagosNuevos,
  required int usuarioId,
  required String motivo,
}) {
  return db.transaction(() async {
    final ventaVieja = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    // Una venta anulada ya revirtió su stock y su caja (`anularVenta`) — sin
    // este chequeo, editarla revertía y reaplicaba todo DE NUEVO encima de
    // eso: stock sumado dos veces, caja movida dos veces, mientras la fila
    // seguía mostrándose "Anulada" en el historial (Regla 6, el rastro
    // tiene que ser fiel a lo que pasó de verdad).
    if (ventaVieja.anuladaEn != null) {
      throw ArgumentError('La venta #$ventaId está anulada, no se puede editar.');
    }
    final lineasViejas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    final pagosViejos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();

    for (final linea in lineasViejas) {
      await _revertirLinea(
        db,
        linea: linea,
        ventaId: ventaId,
        usuarioId: usuarioId,
        motivo: _motivoReversion,
      );
    }

    Caja? cajaNormal;
    Future<Caja> obtenerCajaNormal() async {
      return cajaNormal ??= await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    }

    for (final pago in pagosViejos) {
      final medio = await (db.select(db.mediosDePago)..where((m) => m.id.equals(pago.medioPagoId))).getSingle();
      if (!medio.esEfectivo) continue;
      final caja = await obtenerCajaNormal();
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: ventaVieja.sesionCajaId,
              cajaId: caja.id,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              montoCentavos: -pago.montoCentavos,
              ventaId: Value(ventaId),
              medioPagoId: Value(pago.medioPagoId),
              nota: const Value(_motivoReversion),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );
    }

    await (db.delete(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).go();
    await (db.delete(db.pagos)..where((p) => p.ventaId.equals(ventaId))).go();

    for (final linea in ventaNueva.lineas) {
      await registrarLineaOPromo(db, ventaId: ventaId, usuarioId: usuarioId, linea: linea);
    }

    for (final pago in pagosNuevos) {
      await db.into(db.pagos).insert(
            PagosCompanion.insert(
              ventaId: ventaId,
              medioPagoId: pago.medioPagoId,
              montoCentavos: pago.montoCentavos,
              canal: Value(pago.canal),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
              actualizadoEn: Value(DateTime.now()),
            ),
          );
      if (pago.esEfectivo) {
        final caja = await obtenerCajaNormal();
        await db.into(db.movimientosDeCaja).insert(
              MovimientosDeCajaCompanion.insert(
                sesionCajaId: ventaVieja.sesionCajaId,
                cajaId: caja.id,
                usuarioId: usuarioId,
                tipo: 'VENTA',
                montoCentavos: pago.montoCentavos,
                ventaId: Value(ventaId),
                medioPagoId: Value(pago.medioPagoId),
                nota: const Value(_motivoReaplicacion),
                globalId: Value(generarGlobalId()),
                origenDispositivo: Value(idDispositivoActual),
              ),
            );
      }
    }

    await (db.update(db.ventas)..where((v) => v.id.equals(ventaId))).write(
      VentasCompanion(
        subtotalCentavos: Value(resultadoNuevo.subtotalCentavos),
        recargoCigarrillosCentavos: Value(resultadoNuevo.recargoCigarrillosCentavos),
        descuentoCentavos: Value(resultadoNuevo.descuentoCentavos),
        redondeoCentavos: Value(resultadoNuevo.redondeoCentavos),
        totalCentavos: Value(resultadoNuevo.totalCentavos),
        editadaPorId: Value(usuarioId),
        editadaEn: Value(DateTime.now()),
        motivoEdicion: Value(motivo),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
  });
}

/// Anula una venta cobrada (El dueño, 2026-09-13: eliminar una venta desde el
/// celular) — a diferencia de [editarVenta], NUNCA borra ni reemplaza
/// `lineas_de_venta`/`pagos`: revierte el stock y la caja de lo que la
/// venta tenía (mismo mecanismo, [_revertirLinea] y el mismo criterio de
/// reversión de caja tipo 'VENTA' con monto negativo) y deja la fila de
/// `ventas` marcada, para que el historial la siga mostrando como anulada
/// en vez de que desaparezca (Regla 6, nunca se pierde el rastro).
///
/// Solo se puede anular mientras la sesión de caja de esa venta siga
/// abierta (El dueño: anular una venta de un cierre ya arqueado descuadraría
/// ese arqueo) — a diferencia de editar, que no tiene esa restricción.
Future<void> anularVenta(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
  required String motivo,
}) {
  return db.transaction(() async {
    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    if (venta.anuladaEn != null) {
      throw ArgumentError('La venta #$ventaId ya está anulada.');
    }
    final sesion = await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.id.equals(venta.sesionCajaId))).getSingle();
    if (sesion.estado != 'ABIERTA') {
      throw ArgumentError(
        'Solo se puede anular una venta de una caja todavía abierta.',
      );
    }

    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();

    for (final linea in lineas) {
      await _revertirLinea(
        db,
        linea: linea,
        ventaId: ventaId,
        usuarioId: usuarioId,
        motivo: _motivoReversionAnulacion,
      );
    }

    Caja? cajaNormal;
    Future<Caja> obtenerCajaNormal() async {
      return cajaNormal ??= await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    }

    for (final pago in pagos) {
      final medio = await (db.select(db.mediosDePago)..where((m) => m.id.equals(pago.medioPagoId))).getSingle();
      if (!medio.esEfectivo) continue;
      final caja = await obtenerCajaNormal();
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: venta.sesionCajaId,
              cajaId: caja.id,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              montoCentavos: -pago.montoCentavos,
              ventaId: Value(ventaId),
              medioPagoId: Value(pago.medioPagoId),
              nota: const Value(_motivoReversionAnulacion),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );
    }

    await (db.update(db.ventas)..where((v) => v.id.equals(ventaId))).write(
      VentasCompanion(
        anuladaPorId: Value(usuarioId),
        anuladaEn: Value(DateTime.now()),
        motivoAnulacion: Value(motivo),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
  });
}
