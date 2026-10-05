// Bultos y unidades (El dueño, 2026-10-05: "necesito discriminarlos"). Una factura puede contar en unidades o en bultos (un pack de 6, una
// caja de 24) y NO lo dice: depende del proveedor y hasta del producto. Mezclarlos es grave — el costo por unidad queda 6 o 24 veces mal y el
// stock entra con unidades de menos o de más — así que se propone con dos pistas y SIEMPRE lo confirma el dueño (y se aprende por producto):
//
//   1. Lo que dice la descripción: "(12)", "6X1500", "473X6", "X24", "25U" (`sugerirUnidadesPorBulto`). Es solo una pista: en Serra el
//      "(12)" es el pack del catálogo y la factura cuenta unidades sueltas.
//   2. El costo que ya tenés cargado en el producto (`inferirUnidadesPorCantidad`): si el costo por cantidad de la factura se parece al de tu
//      producto, la factura cuenta unidades; si es unas N veces mayor y la descripción sugiere un pack de N, es un bulto de N.

import 'dart:math' as math;

/// Cuántas unidades trae un bulto según la descripción, o null si no hay una pista clara. Solo una pista: no dice si la factura cuenta
/// bultos o unidades (para eso, [inferirUnidadesPorCantidad]).
int? sugerirUnidadesPorBulto(String descripcion) {
  final t = descripcion.toLowerCase();

  int? valido(int? n) => n != null && n >= 2 && n <= 200 ? n : null;

  // 1) El pack entre paréntesis, completo: "(21)". Uno cortado por la impresión, "(2", no cuenta.
  final parentesis = RegExp(r'\((\d{1,3})\)').firstMatch(t);
  if (parentesis != null) return valido(int.parse(parentesis[1]!));

  // 2) "AxB": si uno es un tamaño (100 o más: "6X1500" son 6 botellas de 1500 cc; "473X6" son 6 latas de 473) el pack es el otro; si los
  // dos son chicos, es un pack de packs ("4X6" = 24).
  final porPor = RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(t);
  if (porPor != null) {
    final a = int.parse(porPor[1]!);
    final b = int.parse(porPor[2]!);
    if (a >= 100 && b < 100) return valido(b);
    if (b >= 100 && a < 100) return valido(a);
    if (a < 100 && b < 100) return valido(a * b);
    return null;
  }

  // 3) "X24" suelto ("CAN X24 473CC"): hasta 100 (un "X200" es más un tamaño que un pack).
  final equis = RegExp(r'\bx\s*(\d{1,3})\b').firstMatch(t);
  if (equis != null) {
    final n = int.parse(equis[1]!);
    if (n <= 100) return valido(n);
  }

  // 4) "50 un", "25U".
  final unidades = RegExp(r'(\d{1,3})\s*(?:unidades|unid|un|u)\b').firstMatch(t);
  if (unidades != null) return valido(int.parse(unidades[1]!));
  return null;
}

/// Qué cuenta la factura en esa línea: [unidades] unidades por cada unidad de la columna cantidad, y por qué.
class UnidadesInferidas {
  const UnidadesInferidas({required this.unidades, required this.motivo});

  final int unidades;
  final String motivo;
}

/// Hasta cuánto se aleja el costo de la factura del que ya tenés para seguir creyendo que es "lo mismo" (una suba de costo normal de varios meses).
const _toleranciaDeCosto = 0.4;

/// Decide, comparando con el costo que ya tenés del producto, si la columna cantidad de la factura cuenta unidades (1) o bultos del
/// tamaño [packSugerido]. Null cuando no se puede decir (sin costo cargado, o un costo que no se parece a ninguna de las dos cosas):
/// ahí se le pregunta al dueño.
///
/// [costoPorCantidadCentavos] es lo que cuesta cada unidad de la columna cantidad (el importe de la línea con todo, dividido por la
/// cantidad); [costoActualPorUnidadCentavos], el costo por unidad que tenés cargado.
UnidadesInferidas? inferirUnidadesPorCantidad({
  required int costoPorCantidadCentavos,
  required int? costoActualPorUnidadCentavos,
  int? packSugerido,
}) {
  final actual = costoActualPorUnidadCentavos;
  if (actual == null || actual <= 0 || costoPorCantidadCentavos <= 0) return null;
  final razon = costoPorCantidadCentavos / actual;
  final limite = math.log(1 + _toleranciaDeCosto);

  final distanciaUnidades = math.log(razon).abs();
  final distanciaPack = packSugerido != null && packSugerido > 1 ? math.log(razon / packSugerido).abs() : double.infinity;

  final esUnidad = distanciaUnidades <= limite;
  final esPack = distanciaPack <= limite;
  if (esUnidad && !esPack) {
    return UnidadesInferidas(unidades: 1, motivo: 'El costo por cantidad se parece al de tu producto: la factura cuenta unidades sueltas.');
  }
  if (esPack && !esUnidad) {
    return UnidadesInferidas(
      unidades: packSugerido!,
      motivo: 'El costo por cantidad es unas ${razon.toStringAsFixed(1)} veces el de tu producto y la descripción sugiere un bulto de $packSugerido.',
    );
  }
  if (esUnidad && esPack) {
    // Las dos hipótesis entran (pack chico y suba de costo grande): gana la más cercana.
    return distanciaUnidades <= distanciaPack
        ? UnidadesInferidas(unidades: 1, motivo: 'El costo por cantidad se parece al de tu producto: la factura cuenta unidades sueltas.')
        : UnidadesInferidas(unidades: packSugerido!, motivo: 'El costo por cantidad se parece a un bulto de $packSugerido de tu producto.');
  }
  return null;
}
