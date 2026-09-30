import 'package:drift/drift.dart';

import 'catalogo.dart';

/// Los artículos que componen una promo (El dueño, 2026-09-29). La promo en sí
/// es una fila de `productos` con `esPromo = true` (para que aparezca en la
/// búsqueda y la grilla como un producto más); esta tabla dice qué lleva. Al
/// cobrarla, la venta se abre en sus artículos: descuenta el stock de cada
/// uno y cada uno cuenta su costo y su proveedor (`registrarLineaDeVenta`).
///
/// Solo artículos por unidad, sin cigarrillos ni otras promos. Local: no se
/// sincroniza.
@DataClassName('ComponentePromo')
class PromoComponentes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get promoId => integer().references(Productos, #id)();
  @ReferenceName('promosDondeEntra')
  IntColumn get productoId => integer().references(Productos, #id)();

  /// Unidades de este artículo por cada unidad de promo.
  IntColumn get cantidad => integer().withDefault(const Constant(1))();
}
