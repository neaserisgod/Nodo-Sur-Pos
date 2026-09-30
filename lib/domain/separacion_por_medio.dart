// De qué medio sale lo que se separa para cada proveedor (El dueño,
// 2026-09-26): "que redistribuya los productos que no sean cigarros que se
// hayan vendido en efectivo para separar en mercado pago teniendo en cuenta
// lo que se vendió de cigarrillos por ese medio".
//
// Dos pasos, y los dos son por el lado del COSTO (lo que se separa es el
// costo real, Regla 5):
//
// 1. Cada línea que no es cigarrillo se separa del medio en que se cobró:
//    si la venta entró por Mercado Pago, esa plata está en MP, no en el
//    cajón. En una venta con cigarrillos, lo cobrado por MP cubre primero a
//    los cigarrillos (hasta su precio de lista) y recién el resto a las
//    demás líneas.
// 2. La lata se lleva al cierre el precio de lista de TODOS los cigarrillos
//    en efectivo (Regla 6), también los cobrados por MP — ese efectivo sale
//    del que dejaron las demás ventas del día. Lo que entró por MP por
//    cigarrillos (con tope en su precio de lista: en un mixto de $1.000 por
//    QR sobre un atado de $4.000, en MP hay $1.000, no $4.000) se corre a MP
//    repartido entre las líneas que quedaron en efectivo ESE día, en
//    proporción a su costo. Por día (sesión de caja) porque es al cerrar
//    cada caja cuando la lata se lleva ese efectivo. Si alcanza para cubrir
//    todo el costo vendido en efectivo del día, lo que sobra es ganancia y
//    queda en MP sin asignar a nadie.
//
// El resultado es por línea: cada proveedor suma después las de su propio
// período (su corte de reposición), sin que el corte cambie cómo se
// repartió el día.

class LineaParaSeparacion {
  /// Id de la línea de venta — la clave del resultado.
  final int lineaId;
  final bool esCigarrillo;

  /// Costo de la línea entera (ya con cantidad/gramos aplicados). Null sin
  /// costo cargado: no entra en ningún reparto (no hay reposición que
  /// separar, Regla 5).
  final int? costoLineaCentavos;

  /// Precio de la línea entera. Para los cigarrillos es el precio de lista
  /// (lo que va a la lata).
  final int precioLineaCentavos;

  /// Sin proveedor no hay a quién separarle — no participa del reparto.
  final bool tieneProveedor;

  const LineaParaSeparacion({
    required this.lineaId,
    required this.esCigarrillo,
    required this.costoLineaCentavos,
    required this.precioLineaCentavos,
    required this.tieneProveedor,
  });

  /// Tiene costo que dividir (aunque no tenga proveedor: igual se muestra).
  bool get _conCosto => !esCigarrillo && costoLineaCentavos != null;

  /// Además participa del reparto del excedente de cigarrillos — sin
  /// proveedor no hay a quién separarle, así que no absorbe nada.
  bool get _separable => _conCosto && tieneProveedor;
}

class VentaParaSeparacion {
  final int sesionId;

  /// Lo cobrado en efectivo y por Mercado Pago en esta venta (suma de sus
  /// pagos) — incluye recargo y redondeo, y ya viene con el descuento
  /// aplicado.
  final int efectivoCentavos;
  final int mpCentavos;
  final List<LineaParaSeparacion> lineas;

  const VentaParaSeparacion({
    required this.sesionId,
    required this.efectivoCentavos,
    required this.mpCentavos,
    required this.lineas,
  });
}

/// De una línea separable, qué parte de su costo y de su ganancia está en
/// Mercado Pago (el resto de cada una, en el cajón).
class ParteMpDeLinea {
  final int costoMpCentavos;
  final int gananciaMpCentavos;

  const ParteMpDeLinea({required this.costoMpCentavos, required this.gananciaMpCentavos});

  @override
  bool operator ==(Object other) =>
      other is ParteMpDeLinea &&
      other.costoMpCentavos == costoMpCentavos &&
      other.gananciaMpCentavos == gananciaMpCentavos;

  @override
  int get hashCode => Object.hash(costoMpCentavos, gananciaMpCentavos);

  @override
  String toString() => 'ParteMpDeLinea(costo: $costoMpCentavos, ganancia: $gananciaMpCentavos)';
}

/// Parte de Mercado Pago del costo y de la ganancia de cada línea con costo
/// — el resto de cada una va del cajón. Los cigarrillos y las líneas sin
/// costo no aparecen en el resultado. Las líneas sin proveedor sí (para
/// mostrarlas), pero solo con el paso 1: no entran en el reparto del
/// excedente de cigarrillos.
///
/// La ganancia sigue la misma lógica que el costo (El dueño, 2026-09-26: "que
/// diferencie entre ganancia o reposición"): paso 1, del medio en que se
/// cobró; paso 2, el efectivo que se lleva la lata sale PRIMERO del costo en
/// efectivo del día (es lo que hay que reponer) y, si alcanza para todo el
/// costo, lo que sobra sale de la ganancia en efectivo — también en
/// proporción, con tope en esa ganancia.
///
/// [ventas] tiene que traer TODAS las ventas (no anuladas) de cada sesión
/// que aparezca: el reparto del paso 2 es sobre el día entero, no solo
/// sobre las líneas de un proveedor.
Map<int, ParteMpDeLinea> parteMpPorLinea(List<VentaParaSeparacion> ventas) {
  final costoMpPropio = <int, int>{};
  final gananciaMpPropia = <int, int>{};
  final sesionDeLinea = <int, int>{};
  final costoEfectivo = <int, int>{};
  final gananciaEfectivo = <int, int>{};
  final excedentePorSesion = <int, int>{};
  final costoEfectivoPorSesion = <int, int>{};
  final gananciaEfectivoPorSesion = <int, int>{};

  for (final venta in ventas) {
    final listaCigarrillos = venta.lineas
        .where((l) => l.esCigarrillo)
        .fold<int>(0, (a, l) => a + l.precioLineaCentavos);
    final mpACigarrillos = venta.mpCentavos < listaCigarrillos ? venta.mpCentavos : listaCigarrillos;
    final mpResto = venta.mpCentavos - mpACigarrillos;
    excedentePorSesion.update(venta.sesionId, (a) => a + mpACigarrillos, ifAbsent: () => mpACigarrillos);

    // Lo que la venta cobró por todo lo que no es cigarrillo (incluye
    // recargo/redondeo, con el descuento ya aplicado) — la base contra la
    // que se mide qué fracción de eso entró por MP.
    final cobradoNoCigarrillos = venta.efectivoCentavos + venta.mpCentavos - listaCigarrillos;
    final mpNoCigarrillos = cobradoNoCigarrillos <= 0
        ? 0
        : (mpResto < cobradoNoCigarrillos ? mpResto : cobradoNoCigarrillos);

    for (final linea in venta.lineas.where((l) => l._conCosto)) {
      final costo = linea.costoLineaCentavos!;
      final ganancia = linea.precioLineaCentavos - costo;
      final costoMp = cobradoNoCigarrillos <= 0 ? 0 : costo * mpNoCigarrillos ~/ cobradoNoCigarrillos;
      final gananciaMp = cobradoNoCigarrillos <= 0 ? 0 : ganancia * mpNoCigarrillos ~/ cobradoNoCigarrillos;
      costoMpPropio[linea.lineaId] = costoMp;
      gananciaMpPropia[linea.lineaId] = gananciaMp;
      if (!linea._separable) continue;
      sesionDeLinea[linea.lineaId] = venta.sesionId;
      costoEfectivo[linea.lineaId] = costo - costoMp;
      // Una línea vendida por debajo del costo no tiene ganancia en efectivo
      // que el excedente pueda absorber.
      final gananciaEf = ganancia - gananciaMp;
      gananciaEfectivo[linea.lineaId] = gananciaEf > 0 ? gananciaEf : 0;
      costoEfectivoPorSesion.update(venta.sesionId, (a) => a + costo - costoMp, ifAbsent: () => costo - costoMp);
      gananciaEfectivoPorSesion.update(
        venta.sesionId,
        (a) => a + gananciaEfectivo[linea.lineaId]!,
        ifAbsent: () => gananciaEfectivo[linea.lineaId]!,
      );
    }
  }

  return {
    for (final lineaId in costoMpPropio.keys)
      if (!sesionDeLinea.containsKey(lineaId))
        lineaId: ParteMpDeLinea(
          costoMpCentavos: costoMpPropio[lineaId]!,
          gananciaMpCentavos: gananciaMpPropia[lineaId]!,
        ),
    for (final MapEntry(key: lineaId, value: sesionId) in sesionDeLinea.entries)
      lineaId: () {
        final excedente = excedentePorSesion[sesionId]!;
        final costoSesion = costoEfectivoPorSesion[sesionId]!;
        final aCosto = excedente < costoSesion ? excedente : costoSesion;
        final restoAGanancia = excedente - aCosto;
        return ParteMpDeLinea(
          costoMpCentavos: costoMpPropio[lineaId]! +
              _proporcional(costoEfectivo[lineaId]!, aCosto, costoSesion),
          gananciaMpCentavos: gananciaMpPropia[lineaId]! +
              _proporcional(
                gananciaEfectivo[lineaId]!,
                restoAGanancia,
                gananciaEfectivoPorSesion[sesionId]!,
              ),
        );
      }(),
  };
}

/// La parte de [aRepartir] que le toca a [parte] de un total [base], con
/// tope en [parte] (nunca se corre más de lo que la línea tiene de ese lado).
int _proporcional(int parte, int aRepartir, int base) {
  if (base <= 0 || aRepartir <= 0) return 0;
  final efectivo = aRepartir < base ? aRepartir : base;
  return parte * efectivo ~/ base;
}
