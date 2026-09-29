// Reposición: el costo real de lo vendido, agrupado por proveedor (Regla 5).
// No es un porcentaje sobre la venta — un % se descapitaliza solo cuando un
// proveedor sube el costo y el precio todavía no se tocó.
//
// Es una suma de costos, no un cobro: se calcula al centavo y solo se
// redondea al peso al mostrarse (a diferencia del triángulo de `markup` y
// del total de venta, que sí redondean como parte del cálculo).

/// Datos mínimos de una línea de venta que hacen falta para agrupar costos
/// por proveedor. No es la línea de venta completa (esa vive en datos, fase 2).
class LineaParaReposicion {
  final String? proveedorId;

  /// Los cigarrillos quedan fuera de acá a propósito: la lata ya recibe el
  /// precio de lista completo de lo vendido, que es exactamente lo que se le
  /// paga a Serra Cigarros (Regla 6). Sumar además su costo acá reservaría
  /// la misma reposición dos veces.
  final bool esCigarrillo;

  /// Costo-foto de la línea. Null cuando no había costo cargado al momento
  /// de la venta: "Varios" nunca lo tiene (Regla 5) y un producto de alta
  /// rápida tampoco hasta completarlo (Regla 9). Son la misma situación de
  /// cara a la reposición — plata vendida cuya reposición no se puede
  /// calcular — así que se tratan igual: no se inventa un costo 0, porque un
  /// 0 haría que el total de reposición pareciera completo sin estarlo.
  final int? costoLineaCentavos;

  final int precioLineaCentavos;

  const LineaParaReposicion({
    required this.proveedorId,
    this.esCigarrillo = false,
    required this.costoLineaCentavos,
    required this.precioLineaCentavos,
  });
}

class ResultadoReposicion {
  /// Costo real vendido por proveedor.
  final Map<String, int> costoRealPorProveedorCentavos;

  /// Precio de venta por proveedor — lo que entró, no lo que costó (Bruno,
  /// ítem 3: "VENDIDO" del papel es precio, no costo — son cosas
  /// distintas y la planilla no puede confundirlas). Cuenta toda línea con
  /// proveedor, tenga costo cargado o no: el costo puede faltar, el precio
  /// cobrado no.
  final Map<String, int> vendidoPorProveedorCentavos;

  /// Ganancia por proveedor = vendido − costo real, solo de las líneas con
  /// costo conocido (Regla 13: "cuánto es la ganancia" es uno de los datos
  /// que Bruno revisa por proveedor al abrir caja, para decidir cuánto
  /// retirar y cuánto dejar como colchón). Mismo criterio de exclusión de
  /// cigarrillos que el resto de esta función — la ganancia de cigarrillos
  /// la administra la lata aparte (Regla 6).
  final Map<String, int> gananciaPorProveedorCentavos;

  /// Lo vendido sin costo cargado ("Varios" + productos de alta rápida
  /// pendientes de completar). Es el indicador de cuánta reposición se está
  /// dejando de calcular, y lo que empuja a completar los costos pendientes.
  final int vendidoSinCostoCentavos;

  const ResultadoReposicion({
    required this.costoRealPorProveedorCentavos,
    required this.vendidoPorProveedorCentavos,
    required this.gananciaPorProveedorCentavos,
    required this.vendidoSinCostoCentavos,
  });
}

ResultadoReposicion calcularReposicion({
  required List<LineaParaReposicion> lineas,
}) {
  final costoPorProveedor = <String, int>{};
  final vendidoPorProveedor = <String, int>{};
  final gananciaPorProveedor = <String, int>{};
  var vendidoSinCosto = 0;

  for (final linea in lineas) {
    if (linea.esCigarrillo) continue;

    final proveedorId = linea.proveedorId;
    if (proveedorId != null) {
      vendidoPorProveedor.update(
        proveedorId,
        (actual) => actual + linea.precioLineaCentavos,
        ifAbsent: () => linea.precioLineaCentavos,
      );
    }

    final costo = linea.costoLineaCentavos;
    if (costo == null) {
      vendidoSinCosto += linea.precioLineaCentavos;
      continue;
    }
    if (proveedorId == null) continue;
    costoPorProveedor.update(
      proveedorId,
      (actual) => actual + costo,
      ifAbsent: () => costo,
    );
    final ganancia = linea.precioLineaCentavos - costo;
    gananciaPorProveedor.update(
      proveedorId,
      (actual) => actual + ganancia,
      ifAbsent: () => ganancia,
    );
  }

  return ResultadoReposicion(
    costoRealPorProveedorCentavos: costoPorProveedor,
    vendidoPorProveedorCentavos: vendidoPorProveedor,
    gananciaPorProveedorCentavos: gananciaPorProveedor,
    vendidoSinCostoCentavos: vendidoSinCosto,
  );
}

/// Separación de fondos por proveedor: "separado" congela un monto, pero
/// no es una cuenta que se detiene — lo que se venda después sigue
/// acumulando aparte, en paralelo, hasta la próxima separación. Al pagar,
/// si se pagó menos de lo separado, esa diferencia no se pierde ni se da
/// por saldada: vuelve a sumarse a "pendiente sin separar" del próximo
/// ciclo (`pendienteBaseCentavos` en `Proveedores`).
///
/// Agnóstica de qué compone [separadoCentavos] — desde Regla 13, eso
/// incluye el colchón (ganancia retenida) que se sumó al costo real al
/// separar, no solo el costo real puro. Esta función no necesita saberlo:
/// solo le importa cuánto se congeló contra cuánto se pagó.
int pendienteBaseTrasPago({
  required int separadoCentavos,
  required int montoPagadoCentavos,
}) {
  final diferencia = separadoCentavos - montoPagadoCentavos;
  return diferencia > 0 ? diferencia : 0;
}

/// Retiro de ganancia real (Regla 13): reparte [gananciaCentavos] entre
/// efectivo y virtual en la misma proporción en que se cobró la venta que
/// la generó (Bruno, 2026-09-06: "de qué medio debe calcularse desde cómo
/// se vendió"). Una venta pagada 100% en un medio manda toda su ganancia a
/// ese lado; un mixto se reparte a prorrata de lo cobrado en cada uno. El
/// resto que no entra exacto en la división cae del lado virtual, para que
/// la suma nunca pierda ni gane un centavo contra [gananciaCentavos]. Es
/// solo el valor de partida — la pantalla deja los dos montos editables
/// antes de confirmar el retiro, para el caso (mixto de varios productos)
/// donde esto es una aproximación, no una atribución exacta.
///
/// Precondición: `efectivoDeLaVentaCentavos + virtualDeLaVentaCentavos` > 0
/// — toda venta real tiene al menos un pago que la cubre entera.
({int efectivoCentavos, int virtualCentavos}) prorratearGananciaPorMedio({
  required int gananciaCentavos,
  required int efectivoDeLaVentaCentavos,
  required int virtualDeLaVentaCentavos,
}) {
  final totalVenta = efectivoDeLaVentaCentavos + virtualDeLaVentaCentavos;
  final efectivo = (gananciaCentavos * efectivoDeLaVentaCentavos) ~/ totalVenta;
  return (
    efectivoCentavos: efectivo,
    virtualCentavos: gananciaCentavos - efectivo,
  );
}
