// Servicios e insumos (`docs/PLAN-SERVICIOS.md`, etapa 2): lo que cuesta un servicio, el precio que conviene cobrarlo y
// para cuántos alcanza lo que hay.
//
// Un INSUMO es lo que el negocio compra y gasta de a poco: un frasco de 15 ml de top coat, una caja de 100 guantes. Se
// compra por envase pero se usa en fracciones (0,4 ml por servicio), así que su stock y lo que usa cada servicio se
// guardan en MILÉSIMAS de su unidad de uso (µl, mg o milésimas de unidad), en enteros: la misma convención que la plata
// (nunca `double`) y que el stock en gramos de los pesables. 0,4 ml = 400.
//
// Un SERVICIO es un producto con duración y una receta: qué insumo usa y cuánto cada vez. No tiene stock propio: para
// cuántos alcanza sale de la receta.
//
// Todo costo calculado redondea hacia arriba al peso entero (convención 5), en una sola operación exacta por pieza:
// sumar insumos con fracciones de centavo y redondear al final, nunca insumo por insumo.

import 'dinero.dart';
import 'ganancia.dart';
import 'promo.dart' show repartirEnProporcion;

/// Milésimas en una unidad de uso.
const int milesimasPorUnidad = 1000;

/// Ganancia buscada con que arranca un servicio nuevo (El dueño, 2026-10-09): 60 % sobre el precio. Se cambia en cada
/// servicio.
const int gananciaBuscadaPorDefectoBp = 6000;

/// En qué se usa un insumo. Las claves se guardan en la base (`productos.unidad_insumo`): no se renombran nunca.
enum UnidadInsumo {
  ml('ml'),
  g('g'),
  u('u');

  const UnidadInsumo(this.clave);

  final String clave;

  /// Cómo se escribe al lado de una cantidad: "0,4 ml", "2 u".
  String get abreviatura => clave;

  String get nombre => switch (this) {
    ml => 'Mililitros',
    g => 'Gramos',
    u => 'Unidades',
  };

  static UnidadInsumo? desdeClave(String? clave) {
    for (final u in values) {
      if (u.clave == clave) return u;
    }
    return null;
  }
}

/// Un insumo con lo que hace falta para las cuentas. [costoEnvaseCentavos] es lo que se paga por un envase y
/// [contenidoEnvaseMilesimas] lo que trae (un frasco de 15 ml = 15000).
class InsumoParaCalculo {
  const InsumoParaCalculo({
    required this.costoEnvaseCentavos,
    required this.contenidoEnvaseMilesimas,
    required this.stockMilesimas,
  });

  final int costoEnvaseCentavos;
  final int contenidoEnvaseMilesimas;
  final int stockMilesimas;
}

/// Una línea de la receta: un insumo y cuánto usa el servicio cada vez, en milésimas.
class UsoDeInsumo {
  const UsoDeInsumo({required this.insumo, required this.cantidadMilesimas});

  final InsumoParaCalculo insumo;
  final int cantidadMilesimas;
}

void _validarInsumo(InsumoParaCalculo i) {
  if (i.contenidoEnvaseMilesimas <= 0) throw ArgumentError('El envase tiene que traer algo (contenido mayor a 0)');
  if (i.costoEnvaseCentavos < 0) throw ArgumentError('El costo del envase no puede ser negativo');
}

/// Lo que cuestan los insumos de una receta, hacia arriba al peso. Exacto: suma las fracciones de centavo de cada insumo
/// (costo del envase × lo usado ÷ contenido) y redondea una sola vez al final.
int costoInsumosCentavos(List<UsoDeInsumo> receta) {
  var numerador = BigInt.zero;
  var denominador = BigInt.one;
  for (final uso in receta) {
    _validarInsumo(uso.insumo);
    if (uso.cantidadMilesimas < 0) throw ArgumentError('Una cantidad de la receta no puede ser negativa');
    final n = BigInt.from(uso.insumo.costoEnvaseCentavos) * BigInt.from(uso.cantidadMilesimas);
    final d = BigInt.from(uso.insumo.contenidoEnvaseMilesimas);
    numerador = numerador * d + n * denominador;
    denominador = denominador * d;
    final mcd = numerador.gcd(denominador);
    if (mcd > BigInt.one) {
      numerador ~/= mcd;
      denominador ~/= mcd;
    }
  }
  final paso = BigInt.from(centavosPorPeso);
  final pasos = _techo(numerador, denominador * paso);
  return (pasos * paso).toInt();
}

BigInt _techo(BigInt a, BigInt b) {
  final q = a ~/ b;
  return a > BigInt.zero && a % b != BigInt.zero ? q + BigInt.one : q;
}

/// Lo que cuesta una línea de la receta sola, hacia arriba al peso: lo que muestra el creador al lado de cada insumo.
int costoDeUsoCentavos(UsoDeInsumo uso) => costoInsumosCentavos([uso]);

/// Lo que cuesta una unidad de uso (un ml, un g, una unidad), hacia arriba al peso: "$ 733/ml".
int costoPorUnidadCentavos(InsumoParaCalculo insumo) {
  _validarInsumo(insumo);
  return redondearFraccionHaciaArriba(
    insumo.costoEnvaseCentavos * milesimasPorUnidad,
    insumo.contenidoEnvaseMilesimas,
    centavosPorPeso,
  );
}

/// La mano de obra de un servicio: lo que vale la hora de trabajo del negocio (El dueño, 2026-10-09: un valor por
/// negocio) por lo que dura, hacia arriba al peso.
int costoManoDeObraCentavos({required int duracionMinutos, required int valorHoraCentavos}) {
  if (duracionMinutos < 0 || valorHoraCentavos < 0) throw ArgumentError('Duración y valor de la hora no pueden ser negativos');
  return redondearFraccionHaciaArriba(valorHoraCentavos * duracionMinutos, 60, centavosPorPeso);
}

/// Lo que le cuesta un servicio al negocio, separado en sus dos partes (el creador las muestra por separado y la suma
/// tiene que dar justo el total).
class CostoDeServicio {
  const CostoDeServicio({required this.insumosCentavos, required this.manoDeObraCentavos});

  final int insumosCentavos;
  final int manoDeObraCentavos;

  int get totalCentavos => insumosCentavos + manoDeObraCentavos;
}

/// El costo de un servicio. Sin mano de obra (el servicio no la suma, o el módulo está apagado), [valorHoraCentavos] es
/// null y esa parte es 0.
CostoDeServicio costoDeServicio({
  required List<UsoDeInsumo> receta,
  required int duracionMinutos,
  int? valorHoraCentavos,
}) {
  return CostoDeServicio(
    insumosCentavos: costoInsumosCentavos(receta),
    manoDeObraCentavos: valorHoraCentavos == null
        ? 0
        : costoManoDeObraCentavos(duracionMinutos: duracionMinutos, valorHoraCentavos: valorHoraCentavos),
  );
}

/// El precio para ganar [gananciaBuscadaBp] sobre el precio con ese costo, hacia arriba a la centena: la misma cuenta que
/// el precio por porcentaje del almacén (Regla 14, `precioConGananciaACentena`). La ganancia buscada es de cada servicio
/// (El dueño, 2026-10-09).
int precioSugeridoCentavos({required int costoCentavos, required int gananciaBuscadaBp}) =>
    precioConGananciaACentena(costoCentavos, gananciaBuscadaBp);

/// Para cuántos servicios alcanza el stock de hoy: el insumo que menos rinde manda. Una receta vacía no se puede calcular
/// (null). Un stock en cero o negativo no alcanza para ninguno.
int? alcanzaPara(List<UsoDeInsumo> receta) {
  int? minimo;
  for (final uso in receta) {
    if (uso.cantidadMilesimas <= 0) continue;
    final rinde = uso.insumo.stockMilesimas <= 0 ? 0 : uso.insumo.stockMilesimas ~/ uso.cantidadMilesimas;
    if (minimo == null || rinde < minimo) minimo = rinde;
  }
  return minimo;
}

/// La posición en la receta del insumo que se acaba primero (el que menos servicios rinde), o null si la receta está vacía.
/// Con un empate gana el primero de la receta.
int? seAcabaPrimero(List<UsoDeInsumo> receta) {
  int? indice;
  int? rindeMinimo;
  for (var k = 0; k < receta.length; k++) {
    final uso = receta[k];
    if (uso.cantidadMilesimas <= 0) continue;
    final rinde = uso.insumo.stockMilesimas <= 0 ? 0 : uso.insumo.stockMilesimas ~/ uso.cantidadMilesimas;
    if (rindeMinimo == null || rinde < rindeMinimo) {
      rindeMinimo = rinde;
      indice = k;
    }
  }
  return indice;
}

/// Lo que gasta una línea cobrada de [cantidad] servicios iguales (Regla 20): cada insumo de la receta con lo que usa en
/// total y su parte del costo de la línea, en el mismo orden que [recetaPorUnidad].
///
/// El costo por servicio es [costoInsumosCentavos], el mismo número que muestra el calculador (una sola fórmula). Ese
/// costo se reparte entre los insumos en proporción a lo que vale lo usado de cada uno, sin perder ni inventar un
/// centavo ([repartirEnProporcion], como el precio de una promo): así la reposición de cada proveedor suma justo el
/// costo de la línea.
({int costoUnitarioCentavos, List<({int milesimas, int costoCentavos})> consumos}) consumosDeLinea(
  List<UsoDeInsumo> recetaPorUnidad, {
  required int cantidad,
}) {
  if (cantidad < 1) throw ArgumentError('La cantidad tiene que ser al menos 1');
  final unitario = costoInsumosCentavos(recetaPorUnidad);
  // Peso de cada insumo: lo que vale lo usado, en milésimas de centavo (solo sirve para repartir, no es un costo).
  final pesos = [
    for (final u in recetaPorUnidad)
      u.insumo.costoEnvaseCentavos * u.cantidadMilesimas * milesimasPorUnidad ~/ u.insumo.contenidoEnvaseMilesimas,
  ];
  final partes = repartirEnProporcion(unitario * cantidad, pesos);
  return (
    costoUnitarioCentavos: unitario,
    consumos: [
      for (var k = 0; k < recetaPorUnidad.length; k++)
        (milesimas: recetaPorUnidad[k].cantidadMilesimas * cantidad, costoCentavos: partes[k]),
    ],
  );
}

/// El primer insumo que no alcanza para lo que pide el carrito entero ([necesario]: insumo → milésimas, ya sumadas todas
/// las líneas), o null si alcanza todo. Lo que pide 0 nunca falta.
K? primerFaltante<K>(Map<K, int> necesario, int Function(K insumo) stockMilesimas) {
  for (final MapEntry(key: insumo, value: pide) in necesario.entries) {
    if (pide > 0 && stockMilesimas(insumo) < pide) return insumo;
  }
  return null;
}

/// Lo que entra al stock con una compra de [envases] envases de [contenidoEnvaseMilesimas] cada uno.
int milesimasDeCompra({required int envases, required int contenidoEnvaseMilesimas}) {
  if (envases <= 0) throw ArgumentError('Hay que comprar al menos un envase');
  if (contenidoEnvaseMilesimas <= 0) throw ArgumentError('El envase tiene que traer algo (contenido mayor a 0)');
  return envases * contenidoEnvaseMilesimas;
}

/// Una cantidad escrita por una persona ("0,4", "1.5", "2") a milésimas. Null si no es un número o si es negativa. Más de
/// tres decimales se redondea al más cercano (nadie mide un insumo más fino que eso).
int? milesimasDesdeTexto(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty || !RegExp(r'^\d*\.?\d*$').hasMatch(limpio) || limpio == '.') return null;
  final partes = limpio.split('.');
  final enteros = int.parse(partes[0].isEmpty ? '0' : partes[0]);
  var decimales = partes.length > 1 ? partes[1] : '';
  var redondeo = 0;
  if (decimales.length > 3) {
    redondeo = int.parse(decimales[3]) >= 5 ? 1 : 0;
    decimales = decimales.substring(0, 3);
  }
  return enteros * milesimasPorUnidad + int.parse(decimales.padRight(3, '0')) + redondeo;
}

/// Milésimas a texto para mostrar, con coma decimal y sin ceros de más: 400 → "0,4", 2000 → "2", 1250 → "1,25".
String textoDeMilesimas(int milesimas) {
  final negativo = milesimas < 0;
  final abs = milesimas.abs();
  final enteros = abs ~/ milesimasPorUnidad;
  final resto = abs % milesimasPorUnidad;
  final decimales = resto == 0 ? '' : ',${resto.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${negativo ? '-' : ''}$enteros$decimales';
}
