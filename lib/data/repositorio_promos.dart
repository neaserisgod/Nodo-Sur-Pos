// Promos (Bruno, 2026-09-29): "se carga precio y costo de 2 o más artículos,
// se le suma el porcentaje, y no se tiene que pasar del precio de lista
// normal". La promo es una fila de `productos` (`esPromo`) para que aparezca en
// la búsqueda y la grilla como un producto más; sus artículos viven en
// `promo_componentes`. Al cobrarla se abre en ellos (`registrarPromoEnVenta`,
// repositorio_ventas.dart), así descuenta el stock de cada artículo.

import 'package:drift/drift.dart';

import '../domain/markup.dart';
import '../domain/promo.dart';
import 'database.dart';
import 'repositorio_productos.dart' show registrarCambioDePrecio;

class ComponenteDePromo {
  const ComponenteDePromo({required this.producto, required this.cantidad});

  final Producto producto;

  /// Unidades de este artículo por cada promo.
  final int cantidad;

  int get costoCentavos => (producto.costoCentavos ?? 0) * cantidad;
  int get listaCentavos => (producto.precioCentavos ?? 0) * cantidad;
}

class PromoConComponentes {
  const PromoConComponentes({required this.promo, required this.componentes});

  final Producto promo;
  final List<ComponenteDePromo> componentes;

  int get costoCentavos => componentes.fold(0, (a, c) => a + c.costoCentavos);

  /// Lo que costarían los artículos sueltos, a precio de lista de hoy.
  int get listaCentavos => componentes.fold(0, (a, c) => a + c.listaCentavos);

  /// La promo quedó por encima de la lista (porque bajó el precio de algún
  /// artículo después de armarla): hay que revisarla.
  bool get pasaDeLista => (promo.precioCentavos ?? 0) > listaCentavos;

  /// Cuántas promos alcanzan con el stock de hoy.
  int get stock => stockDePromo([for (final c in componentes) (stock: c.producto.stock, cantidadPorPromo: c.cantidad)]);
}

/// Las promos con sus artículos, por nombre. [soloActivas] las de la venta.
Future<List<PromoConComponentes>> listarPromos(AppDatabase db, {bool soloActivas = false}) async {
  final promos = await (db.select(db.productos)
        ..where((p) => p.esPromo.equals(true) & (soloActivas ? p.activo.equals(true) : const Constant(true)))
        ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
      .get();
  final resultado = <PromoConComponentes>[];
  for (final promo in promos) {
    resultado.add(PromoConComponentes(promo: promo, componentes: await _componentesDe(db, promo.id)));
  }
  return resultado;
}

Future<List<ComponenteDePromo>> _componentesDe(AppDatabase db, int promoId) async {
  final filas = await (db.select(db.promoComponentes)..where((c) => c.promoId.equals(promoId))).get();
  return [
    for (final f in filas)
      ComponenteDePromo(
        producto: await (db.select(db.productos)..where((p) => p.id.equals(f.productoId))).getSingle(),
        cantidad: f.cantidad,
      ),
  ];
}

/// Qué precio le tocaría a una promo con estos artículos y este porcentaje —
/// lo que muestra el creador mientras se arma, antes de guardar.
class PrecioDePromoCalculado {
  const PrecioDePromoCalculado({
    required this.costoCentavos,
    required this.listaCentavos,
    required this.precioCentavos,
    required this.topeadoPorLista,
  });

  final int costoCentavos;
  final int listaCentavos;
  final int precioCentavos;
  final bool topeadoPorLista;

  /// Una promo por debajo de su costo pierde plata: no se puede guardar.
  bool get cubreElCosto => precioCentavos >= costoCentavos;
}

/// Null si falta algún costo o precio (no hay con qué calcular).
PrecioDePromoCalculado? calcularPromo(List<ComponenteDePromo> componentes, int markupBp) {
  if (componentes.isEmpty) return null;
  for (final c in componentes) {
    if ((c.producto.costoCentavos ?? 0) <= 0 || c.producto.precioCentavos == null) return null;
  }
  final costo = componentes.fold(0, (a, c) => a + c.costoCentavos);
  final lista = componentes.fold(0, (a, c) => a + c.listaCentavos);
  final r = precioDePromo(costoTotalCentavos: costo, precioListaTotalCentavos: lista, markupBp: markupBp);
  return PrecioDePromoCalculado(
    costoCentavos: costo,
    listaCentavos: lista,
    precioCentavos: r.precioCentavos,
    topeadoPorLista: r.topeadoPorLista,
  );
}

/// Crea (o, con [promoId], rehace) una promo. Reglas: al menos dos artículos
/// distintos, todos por unidad, con costo y precio, sin cigarrillos, "Varios"
/// ni otras promos; y el precio resultante tiene que cubrir el costo.
///
/// Devuelve el id de la promo.
Future<int> guardarPromo(
  AppDatabase db, {
  int? promoId,
  required String nombre,
  required List<({int productoId, int cantidad})> articulos,
  required int markupBp,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) throw ArgumentError('Falta el nombre de la promo');
    if (articulos.map((a) => a.productoId).toSet().length < 2) {
      throw ArgumentError('Una promo lleva al menos dos artículos distintos');
    }

    final componentes = <ComponenteDePromo>[];
    for (final a in articulos) {
      if (a.cantidad < 1) throw ArgumentError('La cantidad de cada artículo tiene que ser al menos 1');
      final p = await (db.select(db.productos)..where((t) => t.id.equals(a.productoId))).getSingle();
      if (p.esPesable) throw ArgumentError('"${p.nombre}" es pesable: una promo lleva solo artículos por unidad');
      if (p.tipoCigarrillo != 'ninguno') throw ArgumentError('Los cigarrillos no entran en una promo');
      if (p.esVarios || p.esPromo) throw ArgumentError('"${p.nombre}" no puede formar parte de una promo');
      if ((p.costoCentavos ?? 0) <= 0) throw ArgumentError('"${p.nombre}" no tiene costo cargado');
      if (p.precioCentavos == null) throw ArgumentError('"${p.nombre}" no tiene precio cargado');
      componentes.add(ComponenteDePromo(producto: p, cantidad: a.cantidad));
    }

    final calculo = calcularPromo(componentes, markupBp)!;
    if (!calculo.cubreElCosto) {
      throw ArgumentError('El precio de lista de los artículos no cubre su costo: la promo perdería plata');
    }

    final anterior = promoId == null
        ? null
        : await (db.select(db.productos)..where((p) => p.id.equals(promoId))).getSingle();

    final int id;
    if (anterior == null) {
      id = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: nombreLimpio,
              esPromo: const Value(true),
              precioFijo: const Value(true),
              precioCentavos: Value(calculo.precioCentavos),
              costoCentavos: Value(calculo.costoCentavos),
            ),
          );
    } else {
      id = anterior.id;
      await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
        ProductosCompanion(
          nombre: Value(nombreLimpio),
          precioCentavos: Value(calculo.precioCentavos),
          costoCentavos: Value(calculo.costoCentavos),
          activo: const Value(true),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
      await (db.delete(db.promoComponentes)..where((c) => c.promoId.equals(id))).go();
    }

    for (final c in componentes) {
      await db.into(db.promoComponentes).insert(
            PromoComponentesCompanion.insert(promoId: id, productoId: c.producto.id, cantidad: Value(c.cantidad)),
          );
    }

    await registrarCambioDePrecio(
      db,
      productoId: id,
      usuarioId: usuarioId,
      anterior: anterior,
      precioCentavos: calculo.precioCentavos,
      costoCentavos: calculo.costoCentavos,
      precioPorKiloCentavos: null,
      costoPorKiloCentavos: null,
    );
    return id;
  });
}

/// Activa o desactiva una promo. No se borra: rompería el historial.
Future<void> cambiarActivaPromo(AppDatabase db, {required int promoId, required bool activa}) {
  return (db.update(db.productos)..where((p) => p.id.equals(promoId))).write(ProductosCompanion(activo: Value(activa)));
}

/// Los artículos de cada promo (id de promo → artículos y cantidades). Lo usa
/// la pantalla de venta para saber cuánto stock tiene cada promo
/// (`stockDePromo`) y mostrarla —o esconderla— como a cualquier producto: sin
/// stock, no aparece (Regla 8).
Future<Map<int, List<({int productoId, int cantidad})>>> componentesDePromos(AppDatabase db) async {
  final filas = await db.select(db.promoComponentes).get();
  final resultado = <int, List<({int productoId, int cantidad})>>{};
  for (final f in filas) {
    resultado.putIfAbsent(f.promoId, () => []).add((productoId: f.productoId, cantidad: f.cantidad));
  }
  return resultado;
}
