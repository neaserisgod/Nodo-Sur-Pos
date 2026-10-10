// Datos del tablero de Inicio ("Lenguaje de diseño", 2026-09-26): la fila de
// indicadores del día, ventas por hora, cómo pagaron, más vendidos, stock
// que avisa y pendientes (fiados/encargues). Todo del día calendario, sin
// anuladas — el mismo "hoy" que Separaciones (`separacionesDelDia`), para
// que "Falta separar" de acá y el de Separaciones sean el mismo número.

import 'package:drift/drift.dart';

import '../domain/equilibrio.dart';
import '../domain/tablero.dart';
import 'database.dart';
import 'linea_venta_reconstruccion.dart';
import 'repositorio_pendientes.dart';
import 'repositorio_productos.dart' show sinServiciosNiInsumos;
import 'repositorio_reposicion.dart';

class ProductoConStockBajo {
  const ProductoConStockBajo({
    required this.nombre,
    required this.proveedor,
    required this.esPesable,
    required this.stock,
    this.categoria,
    this.diasQueAlcanza,
  });

  final String nombre;
  final String? proveedor;
  final String? categoria;
  final bool esPesable;

  /// Unidades, o gramos si [esPesable].
  final int stock;

  /// Al ritmo de los últimos 30 días (`domain/tablero.dart`); null sin ventas en ese tiempo.
  final int? diasQueAlcanza;
}

/// Un fiado o encargue pendiente, listo para mostrar (el tablero lo pone
/// donde el mock tenía "Reparaciones", que no es de este negocio).
class PendienteDelTablero {
  const PendienteDelTablero({required this.esFiado, required this.quien, this.detalle, this.montoCentavos, required this.desde});

  final bool esFiado;
  final String quien;
  final String? detalle;
  final int? montoCentavos;
  final DateTime desde;
}

class TableroDelDia {
  const TableroDelDia({
    required this.vendidoCentavos,
    required this.vendidoMismoDiaSemanaPasadaCentavos,
    required this.gananciaCentavos,
    required this.ventaConCostoCentavos,
    required this.vendidoSinCostoCentavos,
    required this.tickets,
    this.unidadesVendidas = 0,
    required this.efectivoCentavos,
    required this.mpCentavos,
    required this.porHora,
    required this.masVendidos,
    required this.stockBajo,
    required this.faltaSepararCentavos,
    required this.proveedoresPendientes,
    required this.proveedoresConAlgoQueSeparar,
    required this.pendientes,
  });

  final int vendidoCentavos;
  final int vendidoMismoDiaSemanaPasadaCentavos;
  final int gananciaCentavos;
  final int ventaConCostoCentavos;
  final int vendidoSinCostoCentavos;
  final int tickets;
  final int unidadesVendidas;
  final int efectivoCentavos;
  final int mpCentavos;
  final Map<int, int> porHora;
  final List<ProductoMasVendido> masVendidos;
  final List<ProductoConStockBajo> stockBajo;
  final int faltaSepararCentavos;
  final int proveedoresPendientes;
  final int proveedoresConAlgoQueSeparar;
  /// Fiados primero (son plata que falta cobrar), después encargues.
  final List<PendienteDelTablero> pendientes;

  /// Margen de lo vendido con costo cargado; null sin ventas con costo.
  double? get margen => ventaConCostoCentavos == 0 ? null : gananciaCentavos / ventaConCostoCentavos;
}

DateTime _inicioDelDia(DateTime d) => DateTime(d.year, d.month, d.day);

Future<TableroDelDia> tableroDelDia(AppDatabase db, {DateTime? ahora}) async {
  final momento = ahora ?? DateTime.now();
  final inicio = _inicioDelDia(momento);
  final fin = inicio.add(const Duration(days: 1));

  Future<List<FilaVenta>> ventasEntre(DateTime desde, DateTime hasta) => (db.select(db.ventas)
        ..where((v) =>
            v.fecha.isBiggerOrEqualValue(desde) & v.fecha.isSmallerThanValue(hasta) & v.anuladaEn.isNull()))
      .get();

  final ventas = await ventasEntre(inicio, fin);
  final semanaPasada = inicio.subtract(const Duration(days: 7));
  final ventasSemanaPasada = await ventasEntre(semanaPasada, semanaPasada.add(const Duration(days: 1)));

  final ids = ventas.map((v) => v.id).toList();
  final lineas = ids.isEmpty
      ? const <FilaLineaVenta>[]
      : await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.isIn(ids))).get();
  final ventaPorId = {for (final v in ventas) v.id: v};
  final ganancia = calcularGananciaBruta(
    lineas: lineas.map((l) => lineaParaReposicionDesde(l, venta: ventaPorId[l.ventaId])).toList(),
  );

  final cobrado = await cobradoDelDia(db, ahora: momento);

  final separaciones = await separacionesDelDia(db, ahora: momento);
  final conAlgo = separaciones.where((s) => s.proveedor != null && (s.faltaSepararCentavos + s.separadoHoyCentavos) > 0);
  // `faltaSepararCentavos` ya es el total (efectivo + MP); la parte MP
  // (`faltaSepararMpCentavos`) está adentro — sumarlas contaba MP dos veces.
  final pendientes = conAlgo.where((s) => s.faltaSepararCentavos > 0);

  return TableroDelDia(
    vendidoCentavos: ventas.fold(0, (a, v) => a + v.totalCentavos),
    vendidoMismoDiaSemanaPasadaCentavos: ventasSemanaPasada.fold(0, (a, v) => a + v.totalCentavos),
    gananciaCentavos: ganancia.gananciaBrutaCentavos,
    ventaConCostoCentavos: ganancia.ventaConCostoCentavos,
    vendidoSinCostoCentavos: ganancia.vendidoSinCostoCentavos,
    tickets: ventas.length,
    unidadesVendidas: unidadesVendidas(lineas.map((l) => (esPesable: l.esPesable, cantidad: l.cantidad ?? 1))),
    efectivoCentavos: cobrado.efectivoCentavos,
    mpCentavos: cobrado.mpCentavos,
    porHora: ventasPorHora(ventas.map((v) => (fecha: v.fecha, totalCentavos: v.totalCentavos))),
    masVendidos: masVendidos(
      lineas.map(
        (l) => (
          clave: l.productoId?.toString() ?? 'libre:${l.nombreProductoFoto}',
          nombre: l.nombreProductoFoto,
          esPesable: l.esPesable,
          cantidad: l.esPesable ? 0 : (l.cantidad ?? 1),
          gramos: l.esPesable ? (l.gramos ?? 0) : 0,
          subtotalCentavos: lineaParaReposicionDesde(l, venta: ventaPorId[l.ventaId]).precioLineaCentavos,
        ),
      ),
    ),
    stockBajo: await _stockQueAvisa(db, momento),
    faltaSepararCentavos: pendientes.fold(0, (a, s) => a + s.faltaSepararCentavos),
    proveedoresPendientes: pendientes.length,
    proveedoresConAlgoQueSeparar: conAlgo.length,
    pendientes: await _pendientes(db),
  );
}

/// "Vendido hace poco" = con alguna venta en los últimos 30 días: lo justo
/// para separar un producto que se trabaja de uno que quedó en 0 hace meses.
Future<List<ProductoConStockBajo>> _stockQueAvisa(AppDatabase db, DateTime momento) async {
  final desde = _inicioDelDia(momento).subtract(const Duration(days: 30));
  final cantidad = db.lineasDeVenta.cantidad.sum();
  final gramos = db.lineasDeVenta.gramos.sum();
  final vendidos = await (db.selectOnly(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..addColumns([db.lineasDeVenta.productoId, cantidad, gramos])
        ..where(db.ventas.fecha.isBiggerOrEqualValue(desde) & db.ventas.anuladaEn.isNull())
        ..groupBy([db.lineasDeVenta.productoId]))
      .map((f) => (id: f.read(db.lineasDeVenta.productoId), cantidad: f.read(cantidad) ?? 0, gramos: f.read(gramos) ?? 0))
      .get();
  final vendidosIds = vendidos.map((v) => v.id).whereType<int>().toSet();
  final vendidoPorProducto = {for (final v in vendidos) if (v.id != null) v.id!: v};
  final nombresCategoria = {for (final c in await db.select(db.categorias).get()) c.id: c.nombre};

  final productos = await (db.select(db.productos)
        ..where((p) => p.activo.equals(true) & p.esVarios.equals(false) & p.esPromo.equals(false) & sinServiciosNiInsumos(p)))
      .get();
  final nombresProveedor = {for (final p in await db.select(db.proveedores).get()) p.id: p.nombre};

  final lista = <ProductoConStockBajo>[];
  for (final p in productos) {
    final stock = p.esPesable ? (p.stockGramos ?? 0) : p.stock;
    final minimo = p.esPesable ? p.stockMinimoGramos : p.stockMinimo;
    if (!avisaPorStock(stock: stock, minimo: minimo, vendidoHacePoco: vendidosIds.contains(p.id))) continue;
    final v = vendidoPorProducto[p.id];
    lista.add(ProductoConStockBajo(
      nombre: p.nombre,
      proveedor: p.proveedorId == null ? null : nombresProveedor[p.proveedorId],
      categoria: p.categoriaId == null ? null : nombresCategoria[p.categoriaId],
      esPesable: p.esPesable,
      stock: stock,
      diasQueAlcanza: diasQueAlcanza(stock: stock, vendido30Dias: v == null ? 0 : (p.esPesable ? v.gramos : v.cantidad)),
    ));
  }
  // Los agotados primero: son los que ya no aparecen en Venta.
  lista.sort((a, b) {
    final porStock = a.stock.compareTo(b.stock);
    return porStock != 0 ? porStock : a.nombre.compareTo(b.nombre);
  });
  return lista;
}

Future<List<PendienteDelTablero>> _pendientes(AppDatabase db) async {
  final clientes = {for (final c in await db.select(db.clientes).get()) c.id: c.nombre};
  String quien(Pendiente p) =>
      (p.clienteId == null ? null : clientes[p.clienteId]) ?? p.nombreLibre ?? 'Sin nombre';
  return [
    for (final p in await listarFiados(db))
      PendienteDelTablero(esFiado: true, quien: quien(p), detalle: p.descripcion, montoCentavos: p.montoCentavos, desde: p.fechaCreacion),
    for (final p in await listarEncargues(db))
      PendienteDelTablero(esFiado: false, quien: quien(p), detalle: p.descripcion, montoCentavos: p.montoCentavos, desde: p.fechaCreacion),
  ];
}
