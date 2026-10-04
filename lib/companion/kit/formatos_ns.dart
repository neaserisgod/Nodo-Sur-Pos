// Textos de precio y stock tal como los muestra el mock (docs/02 §3.2).

import '../cliente_companion.dart' show ProductoCompanion;
import 'piezas_ns.dart' show plataNs;

/// `$ 2.100`, o `$ 14.600/kg` si se vende por peso.
String precioTextoNs(ProductoCompanion p) =>
    p.esPesable ? '${plataNs(p.precioPorKiloCentavos ?? 0)}/kg' : plataNs(p.precioCentavos ?? 0);

/// Gramos a kilos con coma decimal es-AR: 3200 → `3,2 kg`, 2000 → `2 kg`.
String kilosTextoNs(int gramos) {
  final kilos = gramos / 1000;
  final texto = kilos == kilos.roundToDouble() ? kilos.toStringAsFixed(0) : kilos.toStringAsFixed(1).replaceAll('.', ',');
  return '$texto kg';
}

/// Stock en la unidad del producto: `48 u.` o `3,2 kg`.
String stockTextoNs(ProductoCompanion p) => p.esPesable ? kilosTextoNs(p.stockGramos ?? 0) : '${p.stock} u.';

/// Sin stock: 0 o menos.
bool sinStockNs(ProductoCompanion p) => (p.esPesable ? (p.stockGramos ?? 0) : p.stock) <= 0;

/// Poco stock: no está sin stock y quedan 5 unidades o 500 g (docs/02 §3.2).
bool pocoStockNs(ProductoCompanion p) {
  if (sinStockNs(p)) return false;
  return p.esPesable ? (p.stockGramos ?? 0) <= 500 : p.stock <= 5;
}
