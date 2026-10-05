// Cuentas de una factura de compra (El dueño, 2026-10-05: "que calcule todo automáticamente, con revisión humana"). Funciones
// puras: reciben lo que se LEYÓ de la factura (lo transcribe la IA, o se tipea) y devuelven el costo real de cada producto y si
// la factura cierra. La IA nunca hace estas cuentas (Regla 3: una sola fórmula, en un solo lugar).
//
// Cada proveedor imprime el IVA, los descuentos y los impuestos distinto (ver `docs/PLAN-FACTURAS.md`), así que el que lee tiene que
// llevarlo todo a la misma forma antes de llamar acá: por línea, el NETO (sin IVA, ya con el descuento propio de la línea) y los
// impuestos internos si la línea los trae; al pie, el descuento global, los impuestos internos y las percepciones.
//
// El dueño es monotributista: no recupera el IVA. Por eso el costo de un producto es lo que realmente pagó: neto + IVA + impuestos
// internos + su parte de las percepciones, menos su parte de los descuentos del pie.

import 'dinero.dart';
import 'promo.dart' show repartirEnProporcion;

/// Una línea de la factura, ya normalizada.
class LineaDeFactura {
  const LineaDeFactura({
    required this.unidades,
    required this.netoCentavos,
    this.alicuotaBp = 2100,
    this.internosCentavos = 0,
  });

  /// Unidades SUELTAS que entran al stock (bultos × unidades por bulto, si la factura cuenta por bulto).
  final int unidades;

  /// Importe de la línea sin IVA, ya con el descuento de la línea aplicado.
  final int netoCentavos;

  /// Alícuota de IVA en puntos básicos: 2100 = 21 %, 1050 = 10,5 %, 0 = exento.
  final int alicuotaBp;

  /// Impuestos internos de esta línea (cigarrillos, bebidas), si la factura los trae por línea.
  final int internosCentavos;
}

/// La factura completa, con lo que viene "suelto" al pie.
class FacturaDeCompra {
  const FacturaDeCompra({
    required this.lineas,
    this.descuentoGlobalCentavos = 0,
    this.internosAlPieCentavos = 0,
    this.percepcionesCentavos = 0,
  });

  final List<LineaDeFactura> lineas;

  /// Una línea de "Descuento 5 %" en negativo (Puelche), en positivo acá. Se reparte entre los productos.
  final int descuentoGlobalCentavos;

  /// Impuestos internos que la factura trae solo en el pie (Bebidas del Lago).
  final int internosAlPieCentavos;

  /// Percepciones de IIBB y similares (Elpar, Bebidas del Lago).
  final int percepcionesCentavos;
}

class CostoDeLinea {
  const CostoDeLinea({
    required this.netoCentavos,
    required this.ivaCentavos,
    required this.internosCentavos,
    required this.percepcionesCentavos,
    required this.costoUnitarioCentavos,
  });

  /// Neto después de restarle su parte del descuento global.
  final int netoCentavos;
  final int ivaCentavos;

  /// Los propios de la línea más su parte de los del pie.
  final int internosCentavos;

  /// Su parte de las percepciones (0 si se pidió no repartirlas).
  final int percepcionesCentavos;

  /// Lo que costó la línea entera, con todo.
  int get totalCentavos => netoCentavos + ivaCentavos + internosCentavos + percepcionesCentavos;

  /// Costo de UNA unidad, redondeado hacia arriba al peso entero (convención 5: todo costo calculado sube al peso).
  final int costoUnitarioCentavos;
}

/// El costo real de cada línea de [factura], en el mismo orden. Los descuentos del pie bajan el costo de cada producto en
/// proporción a su valor; los impuestos internos y las percepciones lo suben (estas últimas solo con [percepcionesAlCosto]).
///
/// Repartir "en proporción" no pierde ni inventa un centavo: lo repartido suma exactamente lo impreso.
List<CostoDeLinea> costosDeFactura(FacturaDeCompra factura, {bool percepcionesAlCosto = true}) {
  final lineas = factura.lineas;
  if (lineas.isEmpty) return const [];
  _validar(factura);

  final netos = [for (final l in lineas) l.netoCentavos];
  final descuentos = factura.descuentoGlobalCentavos == 0 ? List.filled(lineas.length, 0) : repartirEnProporcion(factura.descuentoGlobalCentavos, netos);
  final netosFinales = [for (var i = 0; i < lineas.length; i++) netos[i] - descuentos[i]];

  final internosPie = factura.internosAlPieCentavos == 0 ? List.filled(lineas.length, 0) : repartirEnProporcion(factura.internosAlPieCentavos, netosFinales);
  final percepciones = factura.percepcionesCentavos == 0 || !percepcionesAlCosto
      ? List.filled(lineas.length, 0)
      : repartirEnProporcion(factura.percepcionesCentavos, netosFinales);

  return [
    for (var i = 0; i < lineas.length; i++)
      () {
        final iva = _iva(netosFinales[i], lineas[i].alicuotaBp);
        final internos = lineas[i].internosCentavos + internosPie[i];
        final total = netosFinales[i] + iva + internos + percepciones[i];
        return CostoDeLinea(
          netoCentavos: netosFinales[i],
          ivaCentavos: iva,
          internosCentavos: internos,
          percepcionesCentavos: percepciones[i],
          costoUnitarioCentavos: redondearFraccionHaciaArriba(total, lineas[i].unidades, centavosPorPeso),
        );
      }(),
  ];
}

class ControlDeFactura {
  const ControlDeFactura({
    required this.subtotalCalculadoCentavos,
    required this.totalCalculadoCentavos,
    required this.diferenciaCentavos,
    required this.toleranciaCentavos,
  });

  /// Suma de los netos menos el descuento global: lo que la factura imprime como "subtotal".
  final int subtotalCalculadoCentavos;

  /// Subtotal + IVA + impuestos internos + percepciones: lo que tendría que decir el total.
  final int totalCalculadoCentavos;

  /// Calculado − impreso. Positivo: lo leído suma de más.
  final int diferenciaCentavos;
  final int toleranciaCentavos;

  /// Cierra si la diferencia es solo el redondeo del proveedor.
  bool get cierra => diferenciaCentavos.abs() <= toleranciaCentavos;
}

/// Compara el total que sale de las líneas leídas con el [totalImpresoCentavos]. Si no cierra, algo se leyó mal (un dígito, una
/// línea de más, un descuento aplicado dos veces) y hay que revisarlo a mano: es la red de seguridad de todo el lector.
///
/// Los proveedores redondean cada línea por su cuenta: en las facturas reales la diferencia es de 1 a 3 centavos, por eso la
/// tolerancia es de 2 centavos más 1 por línea. Un error de lectura es de pesos, nunca de centavos.
ControlDeFactura controlarFactura(FacturaDeCompra factura, {required int totalImpresoCentavos}) {
  final lineas = factura.lineas;
  if (lineas.isNotEmpty) _validar(factura);

  final costos = costosDeFactura(factura);
  final subtotal = costos.fold<int>(0, (a, c) => a + c.netoCentavos);
  final iva = costos.fold<int>(0, (a, c) => a + c.ivaCentavos);
  final internos = lineas.fold<int>(0, (a, l) => a + l.internosCentavos) + factura.internosAlPieCentavos;
  final total = subtotal + iva + internos + factura.percepcionesCentavos;
  return ControlDeFactura(
    subtotalCalculadoCentavos: subtotal,
    totalCalculadoCentavos: total,
    diferenciaCentavos: total - totalImpresoCentavos,
    toleranciaCentavos: 2 + lineas.length,
  );
}

/// El neto de un importe que ya trae el IVA adentro (facturas con "IVA contenido": Bebidas del Lago, Maxiconsumo).
int netoDesdeImporteConIva(int importeCentavos, int alicuotaBp) {
  if (alicuotaBp < 0) throw ArgumentError('La alícuota no puede ser negativa');
  final base = 10000 + alicuotaBp;
  return (importeCentavos * 10000 + base ~/ 2) ~/ base;
}

/// IVA de [netoCentavos], redondeado al centavo más cercano.
int _iva(int netoCentavos, int alicuotaBp) => (netoCentavos * alicuotaBp + 5000) ~/ 10000;

void _validar(FacturaDeCompra f) {
  for (final l in f.lineas) {
    if (l.unidades <= 0) throw ArgumentError('Cada línea tiene que tener al menos una unidad');
    if (l.netoCentavos < 0 || l.internosCentavos < 0 || l.alicuotaBp < 0) throw ArgumentError('Los importes de una línea no pueden ser negativos');
  }
  if (f.descuentoGlobalCentavos < 0 || f.internosAlPieCentavos < 0 || f.percepcionesCentavos < 0) {
    throw ArgumentError('Los montos del pie van en positivo (el descuento se resta solo)');
  }
  final suma = f.lineas.fold<int>(0, (a, l) => a + l.netoCentavos);
  if (f.descuentoGlobalCentavos > suma) throw ArgumentError('El descuento es mayor que la factura entera: está mal leído');
}
