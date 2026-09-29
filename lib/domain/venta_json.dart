// Serialización de `LineaVenta` para el transporte HTTP entre el celular
// (que arma el carrito con lo que ya le devolvió el buscador) y el servidor
// de la companion (que corre las mismas fórmulas que el escritorio sobre esa
// misma línea — Regla 3, ver `servidor_companion.dart`). Nunca se manda un
// `Producto` entero: solo lo que `LineaVenta` necesita, ya congelado
// (costo-foto, Regla 2) en el momento en que se tocó el producto.
//
// Pura, sin Flutter ni SQLite (igual que el resto de `domain/`): la importan
// tanto `lib/companion/` (Android) como `lib/servidor/` (escritorio).

import 'venta.dart';

int _int(dynamic v) => (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();

Map<String, dynamic> lineaVentaAJson(LineaVenta linea) {
  final base = {
    'productoId': linea.productoId,
    'nombreProducto': linea.nombreProducto,
    'proveedorId': linea.proveedorId,
    'esVarios': linea.esVarios,
    'tipoCigarrillo': linea.tipoCigarrillo.name,
  };
  return switch (linea) {
    LineaVentaPorUnidad l => {
      ...base,
      'tipo': 'unidad',
      'cantidad': l.cantidad,
      'precioUnitarioCentavos': l.precioUnitarioCentavos,
      'costoUnitarioCentavos': l.costoUnitarioCentavos,
    },
    LineaVentaPesable l => {
      ...base,
      'tipo': 'pesable',
      'gramos': l.gramos,
      'precioPorKiloCentavos': l.precioPorKiloCentavos,
      'costoPorKiloCentavos': l.costoPorKiloCentavos,
    },
  };
}

LineaVenta lineaVentaDesdeJson(Map<String, dynamic> j) {
  final productoId = j['productoId'] as String;
  final nombreProducto = j['nombreProducto'] as String;
  final proveedorId = j['proveedorId'] as String?;
  final tipoCigarrillo = TipoCigarrillo.values.byName(j['tipoCigarrillo'] as String);

  if (j['tipo'] == 'pesable') {
    return LineaVentaPesable(
      productoId: productoId,
      nombreProducto: nombreProducto,
      proveedorId: proveedorId,
      gramos: _int(j['gramos']),
      precioPorKiloCentavos: _int(j['precioPorKiloCentavos']),
      costoPorKiloCentavos: _intOrNull(j['costoPorKiloCentavos']),
    );
  }
  return LineaVentaPorUnidad(
    productoId: productoId,
    nombreProducto: nombreProducto,
    proveedorId: proveedorId,
    cantidad: _int(j['cantidad']),
    esVarios: j['esVarios'] as bool? ?? false,
    tipoCigarrillo: tipoCigarrillo,
    precioUnitarioCentavos: _int(j['precioUnitarioCentavos']),
    costoUnitarioCentavos: _intOrNull(j['costoUnitarioCentavos']),
  );
}
