// Stock valorizado por proveedor (fase 13, pantalla Proveedores): cuánto
// vale el stock que queda de cada proveedor, a costo Y a precio de venta —
// dos preguntas distintas ("qué me costó lo que tengo" vs. "cuánto vale en
// la góndola"). Corrección post-revisión: El dueño pidió las dos cifras por
// separado ("stock, costo, vendido, ganancia" — cuatro, no tres), no una
// sola cifra a costo mal llamada "stock".

import 'pesables.dart';

/// Datos mínimos de un producto para valorizar su stock. No es el
/// `Producto` completo (eso vive en datos, fase 2) — solo lo que hace falta
/// para esta cuenta.
class ProductoParaValorizar {
  final String? proveedorId;
  final bool esPesable;

  /// Unidades en stock — se ignora si [esPesable].
  final int stock;

  /// Costo-foto por unidad. Null si no está cargado — se ignora si
  /// [esPesable].
  final int? costoCentavos;

  /// Precio de venta por unidad. Null si no está cargado — se ignora si
  /// [esPesable].
  final int? precioCentavos;

  /// Gramos en stock — se ignora si no [esPesable].
  final int? stockGramos;

  /// Costo-foto por kilo. Null si no está cargado — se ignora si no
  /// [esPesable].
  final int? costoPorKiloCentavos;

  /// Precio de venta por kilo. Null si no está cargado — se ignora si no
  /// [esPesable].
  final int? precioPorKiloCentavos;

  const ProductoParaValorizar({
    required this.proveedorId,
    required this.esPesable,
    this.stock = 0,
    this.costoCentavos,
    this.precioCentavos,
    this.stockGramos,
    this.costoPorKiloCentavos,
    this.precioPorKiloCentavos,
  });
}

class ResultadoStockValorizado {
  /// Suma de costo × stock, agrupada por proveedor — "cuánto me costó lo
  /// que tengo".
  final Map<String, int> valorizadoPorProveedorCentavos;

  /// Suma de precio × stock, agrupada por proveedor — "cuánto vale en la
  /// góndola si se vende todo al precio de lista de hoy".
  final Map<String, int> valorizadoAPrecioPorProveedorCentavos;

  /// Cuántos productos de cada proveedor no tienen costo cargado — no se
  /// cuentan como $0 (Regla 5: un producto sin costo no se puede valorizar,
  /// y contarlo como cero escondería justo lo que falta completar).
  final Map<String, int> sinCostoPorProveedor;

  /// Mismo criterio que [sinCostoPorProveedor], pero para precio de venta.
  final Map<String, int> sinPrecioPorProveedor;

  const ResultadoStockValorizado({
    required this.valorizadoPorProveedorCentavos,
    required this.valorizadoAPrecioPorProveedorCentavos,
    required this.sinCostoPorProveedor,
    required this.sinPrecioPorProveedor,
  });
}

/// Agrupa [productos] por proveedor y valoriza el stock de cada uno, a
/// costo y a precio de venta. Un producto sin proveedor asignado no se
/// puede atribuir a nadie y se ignora (mismo criterio que
/// `calcularReposicion` con `proveedorId == null`).
ResultadoStockValorizado calcularStockValorizado({
  required List<ProductoParaValorizar> productos,
}) {
  final valorizado = <String, int>{};
  final valorizadoAPrecio = <String, int>{};
  final sinCosto = <String, int>{};
  final sinPrecio = <String, int>{};

  for (final producto in productos) {
    final proveedorId = producto.proveedorId;
    if (proveedorId == null) continue;

    final costoUnitario = producto.esPesable
        ? producto.costoPorKiloCentavos
        : producto.costoCentavos;
    if (costoUnitario == null) {
      sinCosto.update(proveedorId, (actual) => actual + 1, ifAbsent: () => 1);
    } else {
      final valor = producto.esPesable
          ? subtotalPesable(
              montoPorKiloCentavos: costoUnitario,
              gramos: producto.stockGramos ?? 0,
            )
          : costoUnitario * producto.stock;
      valorizado.update(proveedorId, (actual) => actual + valor, ifAbsent: () => valor);
    }

    final precioUnitario = producto.esPesable
        ? producto.precioPorKiloCentavos
        : producto.precioCentavos;
    if (precioUnitario == null) {
      sinPrecio.update(proveedorId, (actual) => actual + 1, ifAbsent: () => 1);
    } else {
      final valor = producto.esPesable
          ? subtotalPesable(
              montoPorKiloCentavos: precioUnitario,
              gramos: producto.stockGramos ?? 0,
            )
          : precioUnitario * producto.stock;
      valorizadoAPrecio.update(proveedorId, (actual) => actual + valor, ifAbsent: () => valor);
    }
  }

  return ResultadoStockValorizado(
    valorizadoPorProveedorCentavos: valorizado,
    valorizadoAPrecioPorProveedorCentavos: valorizadoAPrecio,
    sinCostoPorProveedor: sinCosto,
    sinPrecioPorProveedor: sinPrecio,
  );
}
