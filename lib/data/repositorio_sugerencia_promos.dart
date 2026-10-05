// Sugerencias de promos (El dueño, 2026-10-05): arma, con las ventas reales de los últimos días, qué pares de artículos
// conviene juntar. Los candidatos y el porcentaje salen de `domain/sugerencia_promos.dart`; el precio, de `calcularPromo`
// (la misma cuenta que hace el creador al guardar). Nada se guarda acá: el dueño elige cuáles crear.

import 'package:drift/drift.dart';

import '../domain/sugerencia_promos.dart';
import 'database.dart';
import 'repositorio_productos.dart' show listarProductos;
import 'repositorio_promos.dart';

class SugerenciaDePromo {
  const SugerenciaDePromo({
    required this.par,
    required this.componentes,
    required this.porcentajeBp,
    required this.calculo,
  });

  final ParSugerido par;

  /// Los dos artículos, una unidad de cada uno.
  final List<ComponenteDePromo> componentes;

  /// Con qué porcentaje de ganancia arranca el creador (el dueño lo puede cambiar).
  final int porcentajeBp;
  final PrecioDePromoCalculado calculo;

  /// Cuánto se ahorra el cliente contra llevar los dos sueltos.
  int get ahorroCentavos => calculo.listaCentavos - calculo.precioCentavos;

  /// Lo que le queda al negocio por cada promo vendida.
  int get gananciaCentavos => calculo.precioCentavos - calculo.costoCentavos;

  /// "Yerba + Galletitas": el nombre de respaldo cuando no hay IA.
  String get nombreSimple =>
      componentes.map((c) => c.producto.nombre).join(' + ');
}

/// Hasta [maximo] promos para armar, de lo que se vendió en los últimos [dias] ([ahora] solo para tests).
///
/// Entran solo artículos que puede llevar una promo (por unidad, sin cigarrillos ni "Varios", con costo, precio y stock) y
/// pares cuyos sueltos dejan ganancia para descontar. Se saltean los pares que ya forman parte de una promo.
Future<List<SugerenciaDePromo>> sugerirPromos(
  AppDatabase db, {
  int dias = 90,
  int maximo = 8,
  DateTime? ahora,
}) async {
  final desde = (ahora ?? DateTime.now()).subtract(Duration(days: dias));

  final productos = {
    for (final p in await listarProductos(db))
      if (!p.esPesable &&
          p.tipoCigarrillo == 'ninguno' &&
          (p.costoCentavos ?? 0) > 0 &&
          p.precioCentavos != null &&
          p.stock > 0)
        p.id: p,
  };

  final filas =
      await (db.select(db.lineasDeVenta).join([
            innerJoin(
              db.ventas,
              db.ventas.id.equalsExp(db.lineasDeVenta.ventaId),
            ),
          ])..where(
            db.ventas.fecha.isBiggerOrEqualValue(desde) &
                db.ventas.anuladaEn.isNull() &
                db.lineasDeVenta.productoId.isNotNull(),
          ))
          .map(
            (r) => (
              venta: r.read(db.ventas.id)!,
              producto: r.read(db.lineasDeVenta.productoId)!,
            ),
          )
          .get();
  final porVenta = <int, Set<int>>{};
  for (final f in filas) {
    porVenta.putIfAbsent(f.venta, () => {}).add(f.producto);
  }

  final existentes = [
    for (final p in await listarPromos(db))
      {for (final c in p.componentes) c.producto.id},
  ];

  // Pide de más: algunos pares caen después por no dejar ganancia para descontar.
  final pares = paresQueSeCompranJuntos(
    porVenta.values.toList(),
    elegibles: productos.keys.toSet(),
    maximo: maximo * 3,
    promosExistentes: existentes,
  );

  final resultado = <SugerenciaDePromo>[];
  for (final par in pares) {
    if (resultado.length >= maximo) break;
    final componentes = [
      ComponenteDePromo(producto: productos[par.productoA]!, cantidad: 1),
      ComponenteDePromo(producto: productos[par.productoB]!, cantidad: 1),
    ];
    final costo = componentes.fold(0, (a, c) => a + c.costoCentavos);
    final lista = componentes.fold(0, (a, c) => a + c.listaCentavos);
    final bp = porcentajeSugeridoDePromoBp(
      costoCentavos: costo,
      precioListaCentavos: lista,
    );
    if (bp == null) continue;
    final calculo = calcularPromo(componentes, bp);
    if (calculo == null ||
        !calculo.cubreElCosto ||
        calculo.precioCentavos >= calculo.listaCentavos) {
      continue;
    }
    resultado.add(
      SugerenciaDePromo(
        par: par,
        componentes: componentes,
        porcentajeBp: bp,
        calculo: calculo,
      ),
    );
  }
  return resultado;
}
