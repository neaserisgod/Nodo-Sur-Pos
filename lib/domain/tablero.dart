// Cuentas del tablero de Inicio ("Lenguaje de diseño", 2026-09-26): ventas
// por hora, más vendidos del día y qué producto avisa por stock. Funciones
// puras; la capa de datos arma las entradas desde la base.

/// Suma de lo vendido por hora del día (0–23). Solo aparecen las horas con
/// venta: el gráfico decide qué rango mostrar.
Map<int, int> ventasPorHora(Iterable<({DateTime fecha, int totalCentavos})> ventas) {
  final porHora = <int, int>{};
  for (final v in ventas) {
    porHora[v.fecha.hour] = (porHora[v.fecha.hour] ?? 0) + v.totalCentavos;
  }
  return porHora;
}

/// Un producto en el ranking del día. Los pesables se rankean por gramos y
/// los de unidad por cantidad, pero en la misma lista: el orden es por
/// plata vendida — "40 unidades" y "3.200 g" no se pueden comparar entre sí,
/// lo que se vendió en pesos sí.
class ProductoMasVendido {
  const ProductoMasVendido({
    required this.nombre,
    required this.esPesable,
    required this.cantidad,
    required this.gramos,
    required this.vendidoCentavos,
  });

  final String nombre;
  final bool esPesable;
  final int cantidad;
  final int gramos;
  final int vendidoCentavos;
}

List<ProductoMasVendido> masVendidos(
  Iterable<({String clave, String nombre, bool esPesable, int cantidad, int gramos, int subtotalCentavos})> lineas, {
  int limite = 5,
}) {
  final acumulado = <String, ProductoMasVendido>{};
  for (final l in lineas) {
    final previo = acumulado[l.clave];
    acumulado[l.clave] = ProductoMasVendido(
      nombre: l.nombre,
      esPesable: l.esPesable,
      cantidad: (previo?.cantidad ?? 0) + l.cantidad,
      gramos: (previo?.gramos ?? 0) + l.gramos,
      vendidoCentavos: (previo?.vendidoCentavos ?? 0) + l.subtotalCentavos,
    );
  }
  final lista = acumulado.values.toList()
    ..sort((a, b) {
      final porPlata = b.vendidoCentavos.compareTo(a.vendidoCentavos);
      return porPlata != 0 ? porPlata : a.nombre.compareTo(b.nombre);
    });
  return lista.take(limite).toList();
}

/// Si un producto tiene que aparecer en "Stock bajo" del tablero.
///
/// - Por debajo del mínimo cargado (el criterio de los mocks).
/// - O en cero/negativo habiéndose vendido hace poco, aunque no tenga
///   mínimo: con stock ≤ 0 el producto desaparece de la búsqueda de Venta
///   (`REGLAS-NEGOCIO.md` §8), así que un más vendido agotado — o con el
///   stock sin actualizar — cuesta ventas todos los días (en septiembre
///   2026 eran 26 productos y la mitad de lo vendido). Un producto viejo
///   que no se vende y quedó en 0 no molesta: no avisa.
bool avisaPorStock({required int stock, required int? minimo, required bool vendidoHacePoco}) {
  if (minimo != null && minimo > 0 && stock < minimo) return true;
  return stock <= 0 && vendidoHacePoco;
}

/// Cuántos días alcanza el stock al ritmo de venta de los últimos 30 días ("alcanza 2 días" en Stock bajo, mock v4).
/// Para abajo: nunca promete más días de los que hay. 0 si está agotado o alcanza menos de un día; null si no se
/// vendió nada en 30 días (no hay ritmo con qué medir). Pesables: gramos contra gramos.
int? diasQueAlcanza({required int stock, required int vendido30Dias}) {
  if (vendido30Dias <= 0) return null;
  if (stock <= 0) return 0;
  return (stock * 30) ~/ vendido30Dias;
}

/// Unidades vendidas del día (tarjeta de Inicio): las de las líneas por unidad, y cada línea de un pesable como una.
int unidadesVendidas(Iterable<({bool esPesable, int cantidad})> lineas) {
  var total = 0;
  for (final l in lineas) {
    total += l.esPesable ? 1 : l.cantidad;
  }
  return total;
}
