// Nivel 1 de la pantalla Proveedores (fase 13): una línea por proveedor con
// las pocas cifras que importan de un vistazo — stock valorizado, vendido y
// ganancia en el período elegido. Distinto de `repositorio_reposicion.dart`
// (que resuelve el nivel 2, "lo que hoy es la reposición"): acá "vendido" y
// "ganancia" son una foto general del negocio, cigarrillos incluidos —
// mismo criterio que `calcularGananciaBruta`, que tampoco los excluye
// (Regla 6: lo que queda afuera de la reposición es la separación de esa
// plata, no la ganancia que representa).

import 'package:drift/drift.dart';

import '../domain/equilibrio.dart';
import '../domain/periodo.dart';
import '../domain/stock_valorizado.dart';
import 'database.dart';
import 'linea_venta_reconstruccion.dart';

class ResumenProveedorNivel1 {
  final Proveedor proveedor;

  /// Stock valorizado a PRECIO de venta — "cuánto vale en la góndola"
  /// (corrección post-revisión: Bruno pidió cuatro cifras — stock, costo,
  /// vendido, ganancia — no tres. Antes esta columna mostraba el valor a
  /// costo bajo el nombre "Stock", confundiendo las dos preguntas).
  final int stockValorizadoCentavos;

  /// Stock valorizado a COSTO — "cuánto me costó lo que tengo".
  final int costoValorizadoCentavos;

  /// Cuántos productos de este proveedor no tienen costo cargado — el
  /// valorizado a costo de esos no está incluido en
  /// [costoValorizadoCentavos] (Regla 5: no se inventa un costo 0).
  final int productosSinCostoCantidad;

  /// Mismo criterio que [productosSinCostoCantidad], para precio de venta —
  /// esos productos no están incluidos en [stockValorizadoCentavos].
  final int productosSinPrecioCantidad;

  final int vendidoCentavos;
  final int gananciaBrutaCentavos;

  const ResumenProveedorNivel1({
    required this.proveedor,
    required this.stockValorizadoCentavos,
    required this.costoValorizadoCentavos,
    required this.productosSinCostoCantidad,
    required this.productosSinPrecioCantidad,
    required this.vendidoCentavos,
    required this.gananciaBrutaCentavos,
  });

  /// true si no hubo venta de este proveedor en el período — se manda al
  /// final de la lista y se apaga visualmente (corrección post-revisión:
  /// "11 de 14 proveedores en cero ocupan media pantalla").
  bool get sinMovimiento => vendidoCentavos == 0;
}

/// Cifras agregadas de un conjunto de productos que no corresponde a un
/// proveedor puntual: "Todos" (todo el catálogo) y "Sin proveedor" (fase 13,
/// primeros dos ítems de `ListaMaestra` en la pantalla Proveedores). Misma
/// forma que [ResumenProveedorNivel1] menos lo que no tiene sentido sin un
/// proveedor real: `separadoCentavos` (no hay reposición sin proveedor) y
/// `sinMovimiento` (acá no se ordena una lista).
class ResumenAgregadoProductos {
  final int stockValorizadoCentavos;
  final int costoValorizadoCentavos;
  final int productosSinCostoCantidad;
  final int productosSinPrecioCantidad;
  final int vendidoCentavos;
  final int gananciaBrutaCentavos;

  const ResumenAgregadoProductos({
    required this.stockValorizadoCentavos,
    required this.costoValorizadoCentavos,
    required this.productosSinCostoCantidad,
    required this.productosSinPrecioCantidad,
    required this.vendidoCentavos,
    required this.gananciaBrutaCentavos,
  });
}

/// Único punto de conteo de vendido/ganancia en un rango de fechas — lo usan
/// [resumenTodosLosProductos] y [resumenProductosSinProveedor], mismo motivo
/// que ya separaba esta cuenta del loop de `resumenProveedoresNivel1`
/// (Convención 3: una fórmula, un solo lugar).
Future<({int vendido, int ganancia})> _ventasEnRango(
  AppDatabase db, {
  required DateTime? inicio,
  required Expression<bool> filtroLineas,
}) async {
  final query = db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  // Sin ventas anuladas (Bruno, 2026-09-26): una venta revertida no generó
  // nada que reponer, ni vendido, ni ganancia.
  ])..where(
      filtroLineas &
          db.ventas.anuladaEn.isNull() &
          (inicio == null ? const Constant(true) : db.ventas.fecha.isBiggerOrEqualValue(inicio)),
    );
  final filas = await query.get();
  final lineas = filas.map((fila) => lineaParaReposicionDesde(fila.readTable(db.lineasDeVenta), venta: fila.readTable(db.ventas))).toList();
  final ganancia = calcularGananciaBruta(lineas: lineas);
  return (
    vendido: ganancia.ventaConCostoCentavos + ganancia.vendidoSinCostoCentavos,
    ganancia: ganancia.gananciaBrutaCentavos,
  );
}

/// "Desde el último pago" es, por definición, la fecha de pago de UN
/// proveedor puntual (`Proveedor.ultimoPagoFecha`) — sin un proveedor real
/// elegido no hay una fecha de la que partir, así que folder a "cuenta desde
/// siempre" (mismo criterio que ya usa `resumenProveedoresNivel1` cuando un
/// proveedor nunca pagó). Es una decisión técnica razonable, no de negocio:
/// avisar acá en vez de esconderlo en el llamador.
DateTime? _inicioParaAgregado(PeriodoResumen periodo, DateTime ahora) {
  if (periodo == PeriodoResumen.desdeUltimoPago) return null;
  return inicioDePeriodo(periodo, ahora);
}

ResumenAgregadoProductos _resumenDesdeValorizadoYVentas(
  ResultadoStockValorizado valorizado,
  String clave,
  ({int vendido, int ganancia}) ventas,
) {
  return ResumenAgregadoProductos(
    stockValorizadoCentavos: valorizado.valorizadoAPrecioPorProveedorCentavos[clave] ?? 0,
    costoValorizadoCentavos: valorizado.valorizadoPorProveedorCentavos[clave] ?? 0,
    productosSinCostoCantidad: valorizado.sinCostoPorProveedor[clave] ?? 0,
    productosSinPrecioCantidad: valorizado.sinPrecioPorProveedor[clave] ?? 0,
    vendidoCentavos: ventas.vendido,
    gananciaBrutaCentavos: ventas.ganancia,
  );
}

const _claveAgregado = 'agregado';

/// "Todos" (fase 13, primer ítem de `ListaMaestra` en Proveedores): el
/// catálogo entero, sin importar el proveedor. Reusa `calcularStockValorizado`
/// con una única clave para todos los productos en vez de agruparlos por
/// proveedor — a diferencia de `resumenProveedoresNivel1`, acá SÍ entran los
/// productos sin proveedor asignado (Convención 3: misma fórmula, un caso más).
Future<ResumenAgregadoProductos> resumenTodosLosProductos(
  AppDatabase db, {
  required PeriodoResumen periodo,
  required DateTime ahora,
}) async {
  // Sin "Varios" (Regla 5): el sentinela del botón de venta rápida no tiene
  // precio ni costo propio — sumarlo contaría un "producto sin completar"
  // que en realidad no es un producto editable.
  final productos = await (db.select(db.productos)..where((p) => p.esVarios.equals(false))).get();
  final valorizado = calcularStockValorizado(
    productos: [
      for (final p in productos)
        ProductoParaValorizar(
          proveedorId: _claveAgregado,
          esPesable: p.esPesable,
          stock: p.stock,
          costoCentavos: p.costoCentavos,
          precioCentavos: p.precioCentavos,
          stockGramos: p.stockGramos,
          costoPorKiloCentavos: p.costoPorKiloCentavos,
          precioPorKiloCentavos: p.precioPorKiloCentavos,
        ),
    ],
  );
  final ventas = await _ventasEnRango(
    db,
    inicio: _inicioParaAgregado(periodo, ahora),
    filtroLineas: const Constant(true),
  );
  return _resumenDesdeValorizadoYVentas(valorizado, _claveAgregado, ventas);
}

/// "Sin proveedor" (fase 13, segundo ítem de `ListaMaestra` en Proveedores):
/// productos de alta rápida u orfandad de catálogo, sin proveedor asignado.
/// Mismo motivo que [resumenTodosLosProductos] para excluir "Varios".
Future<ResumenAgregadoProductos> resumenProductosSinProveedor(
  AppDatabase db, {
  required PeriodoResumen periodo,
  required DateTime ahora,
}) async {
  final productos =
      await (db.select(db.productos)..where((p) => p.proveedorId.isNull() & p.esVarios.equals(false))).get();
  final valorizado = calcularStockValorizado(
    productos: [
      for (final p in productos)
        ProductoParaValorizar(
          proveedorId: _claveAgregado,
          esPesable: p.esPesable,
          stock: p.stock,
          costoCentavos: p.costoCentavos,
          precioCentavos: p.precioCentavos,
          stockGramos: p.stockGramos,
          costoPorKiloCentavos: p.costoPorKiloCentavos,
          precioPorKiloCentavos: p.precioPorKiloCentavos,
        ),
    ],
  );
  final ventas = await _ventasEnRango(
    db,
    inicio: _inicioParaAgregado(periodo, ahora),
    filtroLineas: db.lineasDeVenta.proveedorIdFoto.isNull(),
  );
  return _resumenDesdeValorizadoYVentas(valorizado, _claveAgregado, ventas);
}

/// Resumen de cada proveedor activo para el nivel 1. A diferencia de
/// `reposicionActual`, incluye a Serra Cigarros: acá no es una fila en cero
/// permanente (Regla 6 solo excluye cigarrillos de la reposición, no de la
/// venta ni de la ganancia que representan) — Serra Cigarros vende de
/// verdad y esa venta tiene que verse en su fila.
Future<List<ResumenProveedorNivel1>> resumenProveedoresNivel1(
  AppDatabase db, {
  required PeriodoResumen periodo,
  required DateTime ahora,
}) async {
  final proveedores = await (db.select(
    db.proveedores,
  )..where((p) => p.activo.equals(true))).get();
  final productos = await db.select(db.productos).get();

  final stockValorizado = calcularStockValorizado(
    productos: [
      for (final p in productos)
        if (p.proveedorId != null)
          ProductoParaValorizar(
            proveedorId: p.proveedorId.toString(),
            esPesable: p.esPesable,
            stock: p.stock,
            costoCentavos: p.costoCentavos,
            precioCentavos: p.precioCentavos,
            stockGramos: p.stockGramos,
            costoPorKiloCentavos: p.costoPorKiloCentavos,
            precioPorKiloCentavos: p.precioPorKiloCentavos,
          ),
    ],
  );

  // "Hoy"/"Semana"/"Mes" cortan igual para todos los proveedores — se
  // calcula una sola vez. "Desde el último pago" es por proveedor (cada
  // fila usa su propia fecha) — el filtro sigue siendo por proveedor, pero
  // ya no en una consulta por proveedor: se traen todas las líneas de
  // todos los proveedores activos en una sola consulta (antes eran hasta
  // ~15 round-trips secuenciales, uno por proveedor) y el corte de fecha
  // por proveedor se aplica en memoria sobre esas filas ya traídas.
  final inicioComun = periodo == PeriodoResumen.desdeUltimoPago
      ? null
      : inicioDePeriodo(periodo, ahora);

  final idsProveedores = proveedores.map((p) => p.id).toList();
  final filasPorProveedor = <int, List<(FilaLineaVenta linea, FilaVenta venta)>>{};
  if (idsProveedores.isNotEmpty) {
    final query = db.select(db.lineasDeVenta).join([
      innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
    ])..where(db.lineasDeVenta.proveedorIdFoto.isIn(idsProveedores) & db.ventas.anuladaEn.isNull());
    final filas = await query.get();
    for (final fila in filas) {
      final linea = fila.readTable(db.lineasDeVenta);
      filasPorProveedor.putIfAbsent(linea.proveedorIdFoto!, () => []).add((linea, fila.readTable(db.ventas)));
    }
  }

  final resultados = <ResumenProveedorNivel1>[];
  for (final proveedor in proveedores) {
    final inicio = periodo == PeriodoResumen.desdeUltimoPago
        ? inicioDePeriodo(periodo, ahora, ultimoPago: proveedor.ultimoPagoFecha)
        : inicioComun;

    final lineas = (filasPorProveedor[proveedor.id] ?? const [])
        .where((par) => inicio == null || !par.$2.fecha.isBefore(inicio))
        .map((par) => lineaParaReposicionDesde(par.$1, venta: par.$2))
        .toList();
    final ganancia = calcularGananciaBruta(lineas: lineas);

    final clave = proveedor.id.toString();
    resultados.add(
      ResumenProveedorNivel1(
        proveedor: proveedor,
        stockValorizadoCentavos:
            stockValorizado.valorizadoAPrecioPorProveedorCentavos[clave] ?? 0,
        costoValorizadoCentavos:
            stockValorizado.valorizadoPorProveedorCentavos[clave] ?? 0,
        productosSinCostoCantidad:
            stockValorizado.sinCostoPorProveedor[clave] ?? 0,
        productosSinPrecioCantidad:
            stockValorizado.sinPrecioPorProveedor[clave] ?? 0,
        vendidoCentavos:
            ganancia.ventaConCostoCentavos + ganancia.vendidoSinCostoCentavos,
        gananciaBrutaCentavos: ganancia.gananciaBrutaCentavos,
      ),
    );
  }

  // Los proveedores sin venta en el período se mandan al final (corrección
  // post-revisión) — siguen ahí, solo dejan de competir por la atención con
  // los que sí tuvieron movimiento. `List.sort` es estable en Dart: dentro
  // de cada grupo el orden relativo que ya traía `proveedores` no cambia.
  resultados.sort((a, b) {
    if (a.sinMovimiento == b.sinMovimiento) return 0;
    return a.sinMovimiento ? 1 : -1;
  });
  return resultados;
}
