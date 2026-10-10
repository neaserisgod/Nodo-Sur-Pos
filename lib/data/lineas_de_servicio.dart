// La línea de un servicio cobrado, vista por proveedor (Regla 20). En `lineas_de_venta` queda UNA línea ("Kapping": la que
// dicen el ticket y el historial), con el costo de todos sus insumos y sin proveedor. Pero a cada proveedor se le repone lo
// que costaron SUS insumos: la reposición, las Separaciones y los resúmenes por proveedor leen esa línea repartida en
// partes, una por insumo usado (`consumos_de_linea`), cada una con el proveedor y el costo-foto del insumo y su parte del
// precio (en proporción al costo, como el precio de una promo entre sus artículos). La suma de las partes es justo la línea:
// lo vendido, el costo y la ganancia no cambian, solo de quién son.
//
// Un solo lugar (Regla 3) para que todas esas cuentas repartan igual. El resto del código (ticket, historial, ganancia del
// día, equilibrio) sigue viendo la línea entera.

import 'package:drift/drift.dart';

import '../domain/promo.dart' show repartirEnProporcion;
import 'database.dart';

/// [pares] con cada línea de servicio que tiene consumos reemplazada por sus partes. Las demás quedan igual, en el mismo
/// orden. Una línea de servicio sin consumos (un servicio sin insumos) queda entera: no tiene a quién reponerle nada.
Future<List<(FilaLineaVenta, FilaVenta)>> conServiciosRepartidos(AppDatabase db, List<(FilaLineaVenta, FilaVenta)> pares) async {
  final idsServicio = [for (final (l, _) in pares) if (l.esServicio) l.id];
  if (idsServicio.isEmpty) return pares;

  final filas = await (db.select(db.consumosDeLinea).join([
    innerJoin(db.productos, db.productos.id.equalsExp(db.consumosDeLinea.insumoId)),
  ])
        ..where(db.consumosDeLinea.lineaVentaId.isIn(idsServicio))
        ..orderBy([OrderingTerm.asc(db.consumosDeLinea.id)]))
      .get();
  final porLinea = <int, List<(FilaConsumoDeLinea, Producto)>>{};
  for (final f in filas) {
    final c = f.readTable(db.consumosDeLinea);
    porLinea.putIfAbsent(c.lineaVentaId, () => []).add((c, f.readTable(db.productos)));
  }

  return [
    for (final (linea, venta) in pares)
      if (!linea.esServicio || porLinea[linea.id] == null)
        (linea, venta)
      else
        for (final parte in partesDeServicio(linea, porLinea[linea.id]!)) (parte, venta),
  ];
}

/// Las partes de una línea de servicio, una por consumo. Cada parte es una línea de una unidad con el precio que le toca,
/// el costo del insumo y su proveedor. Su id es el del consumo en negativo: no es una fila de `lineas_de_venta` y no se
/// confunde con ninguna.
List<FilaLineaVenta> partesDeServicio(FilaLineaVenta linea, List<(FilaConsumoDeLinea, Producto)> consumos) {
  final precioLinea = linea.precioUnitarioCentavos * (linea.cantidad ?? 1);
  final precios = repartirEnProporcion(precioLinea, [for (final (c, _) in consumos) c.costoCentavos]);
  return [
    for (var k = 0; k < consumos.length; k++)
      FilaLineaVenta(
        id: -consumos[k].$1.id,
        ventaId: linea.ventaId,
        productoId: consumos[k].$1.insumoId,
        nombreProductoFoto: '${consumos[k].$2.nombre} · ${linea.nombreProductoFoto}',
        proveedorIdFoto: consumos[k].$1.proveedorIdFoto,
        esVarios: false,
        tipoCigarrillo: 'ninguno',
        esPesable: false,
        esServicio: false,
        cantidad: 1,
        precioUnitarioCentavos: precios[k],
        // Un insumo sin costo cargado deja su parte "sin costo" (se avisa, Regla 4), no una ganancia del 100 %.
        costoUnitarioCentavos: consumos[k].$1.costoCentavos,
        globalId: null,
        origenDispositivo: null,
        actualizadoEn: null,
      ),
  ];
}
