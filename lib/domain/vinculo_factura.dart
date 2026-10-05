// Vincular cada línea de una factura de compra con un producto del comercio (El dueño, 2026-10-05). Funciones puras. Las facturas
// describen los productos con abreviaturas y códigos propios ("BG ALF AGUILA MINITORTA BL 69G(21)"), distintos de los nombres del
// comercio, así que se prueba en este orden y se frena en lo primero que da un resultado:
//
//   1. Lo que ya se aprendió de ese proveedor (por código y por descripción): confianza alta.
//   2. El código de barras impreso en la línea: confianza alta.
//   3. El parecido de nombre, con las abreviaturas: confianza media (se confirma una vez; después queda aprendido y pasa a alta).
//
// Una IA puede ayudar con lo que queda dudoso (`servicios/vinculador_ia.dart`), pero lo decide siempre el que confirma. Nunca se
// inventa un vínculo: si no hay un parecido claro, la línea queda sin vincular y se ofrecen alternativas.

import 'normalizacion_texto.dart';

class ProductoCandidato {
  const ProductoCandidato({required this.id, required this.nombre, this.codigoBarras, this.proveedorId});

  final int id;
  final String nombre;
  final String? codigoBarras;
  final int? proveedorId;
}

enum TipoClaveVinculo { codigo, descripcion }

/// Un vínculo ya confirmado por el dueño: la clave (código o descripción normalizados) de un proveedor apunta a un producto.
class VinculoAprendido {
  const VinculoAprendido({required this.tipoClave, required this.clave, required this.productoId, this.unidadesPorCantidad = 1});

  final TipoClaveVinculo tipoClave;
  final String clave;
  final int productoId;

  /// Cuántas unidades del producto entran por cada unidad de la columna "cantidad" de la factura (un bulto de 6 = 6).
  final int unidadesPorCantidad;
}

class LineaAVincular {
  const LineaAVincular({required this.descripcion, this.codigo});

  final String? codigo;
  final String descripcion;
}

/// Cuánto se puede confiar en el vínculo propuesto: verde, amarillo (confirmar), rojo (sin vincular).
enum ConfianzaVinculo { alta, media, ninguna }

enum OrigenVinculo { aprendido, codigoDeBarras, nombre, ia, manual }

class PropuestaDeVinculo {
  const PropuestaDeVinculo({
    required this.confianza,
    this.productoId,
    this.origen,
    this.puntajePct = 0,
    this.alternativas = const [],
    this.unidadesPorCantidad = 1,
  });

  /// Null si no hay un vínculo claro (confianza `ninguna`).
  final int? productoId;
  final ConfianzaVinculo confianza;
  final OrigenVinculo? origen;

  /// Parecido de nombre de 0 a 100 (0 si el vínculo vino de lo aprendido o del código de barras).
  final int puntajePct;

  /// Otros productos posibles, del más al menos parecido, para que el dueño elija.
  final List<int> alternativas;
  final int unidadesPorCantidad;
}

// ─── Claves ───────────────────────────────────────────────────────────────

/// El código del proveedor para comparar: sin mayúsculas, símbolos ni ceros a la izquierda ("00001421" y "1421" son el mismo).
String claveDeCodigo(String? codigo) {
  final limpio = normalizarTexto(codigo ?? '').replaceAll(RegExp(r'[^a-z0-9]'), '');
  return limpio.replaceFirst(RegExp(r'^0+(?=.)'), '');
}

/// La descripción para comparar: sin acentos ni mayúsculas, sin el pack entre paréntesis, con las unidades parejas ("69 gr" = "69g",
/// "473 cc" = "473ml") y sin palabras de relleno. Es la clave con la que se aprende un vínculo por descripción.
String claveDeDescripcion(String descripcion) => _tokens(descripcion).join(' ');

const _relleno = {'de', 'del', 'la', 'el', 'los', 'las', 'con', 'sin', 'x', 'y', 'en', 'un', 'una', 'por', 'para', 'paq', 'pack', 'pq', 'u', 'unid'};

List<String> _tokens(String texto) {
  var t = normalizarTexto(texto);
  // El pack entre paréntesis, a veces cortado por la impresión: "(21)", "(2".
  t = t.replaceAll(RegExp(r'\(\s*\d*\s*\)?'), ' ');
  // Decimales: "2,25" y "71.5" → "225" y "715" (los dos lados pasan por lo mismo, así que comparan igual).
  t = t.replaceAllMapped(RegExp(r'(\d)[.,](\d)'), (m) => '${m[1]}${m[2]}');
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*(?:gramos|grs|gr|g)\b'), (m) => '${m[1]}g');
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*(?:cc|ml)\b'), (m) => '${m[1]}ml');
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*(?:litros|litro|lts|lt|l)\b'), (m) => '${m[1]}l');
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*(?:kilos|kilo|kgs|kg)\b'), (m) => '${m[1]}kg');
  // "X200" = "200".
  t = t.replaceAllMapped(RegExp(r'\bx(\d+)\b'), (m) => '${m[1]}');
  return [
    for (final p in t.split(RegExp(r'[^a-z0-9]+')))
      if (p.isNotEmpty && !_relleno.contains(p)) p,
  ];
}

// ─── Proponer vínculos ────────────────────────────────────────────────────

/// El mínimo de parecido para proponer un producto, y cuánto tiene que sacarle al segundo para no dudar entre los dos.
const _puntajeMinimo = 0.6;
const _ventajaMinima = 0.08;

/// El mínimo para ofrecerlo como alternativa.
const _puntajeAlternativa = 0.35;

/// Bonus por ser del mismo proveedor de la factura: mayor que [_ventajaMinima], así desempata de verdad.
const _bonusMismoProveedor = 0.1;

/// Una propuesta por línea de [lineas], en el mismo orden. [vinculos] es lo aprendido de este proveedor y [proveedorId] su id (para
/// preferir sus productos).
List<PropuestaDeVinculo> proponerVinculos({
  required List<LineaAVincular> lineas,
  required List<ProductoCandidato> catalogo,
  List<VinculoAprendido> vinculos = const [],
  int? proveedorId,
}) {
  final ids = {for (final p in catalogo) p.id};
  final porCodigo = <String, VinculoAprendido>{};
  final porDescripcion = <String, VinculoAprendido>{};
  for (final v in vinculos) {
    if (!ids.contains(v.productoId)) continue; // el producto ya no existe
    (v.tipoClave == TipoClaveVinculo.codigo ? porCodigo : porDescripcion)[v.clave] = v;
  }
  final porEan = <String, ProductoCandidato>{
    for (final p in catalogo)
      if (_soloDigitos(p.codigoBarras).length >= 8) _soloDigitos(p.codigoBarras): p,
  };
  final tokensDeProductos = {for (final p in catalogo) p.id: _tokens(p.nombre)};

  return [
    for (final l in lineas)
      () {
        final aprendido = porCodigo[claveDeCodigo(l.codigo)] ?? porDescripcion[claveDeDescripcion(l.descripcion)];
        if (aprendido != null && (claveDeCodigo(l.codigo).isNotEmpty || claveDeDescripcion(l.descripcion).isNotEmpty)) {
          return PropuestaDeVinculo(
            productoId: aprendido.productoId,
            confianza: ConfianzaVinculo.alta,
            origen: OrigenVinculo.aprendido,
            unidadesPorCantidad: aprendido.unidadesPorCantidad,
          );
        }
        final digitos = _soloDigitos(l.codigo);
        if ({8, 12, 13, 14}.contains(digitos.length) && porEan.containsKey(digitos)) {
          return PropuestaDeVinculo(productoId: porEan[digitos]!.id, confianza: ConfianzaVinculo.alta, origen: OrigenVinculo.codigoDeBarras);
        }
        return _porNombre(l, catalogo, tokensDeProductos, proveedorId);
      }(),
  ];
}

PropuestaDeVinculo _porNombre(LineaAVincular l, List<ProductoCandidato> catalogo, Map<int, List<String>> tokensDeProductos, int? proveedorId) {
  final tokens = _tokens(l.descripcion);
  final puntajes = <({int id, double puntaje})>[];
  for (final p in catalogo) {
    var puntaje = _parecido(tokens, tokensDeProductos[p.id]!);
    if (puntaje <= 0) continue;
    if (proveedorId != null && p.proveedorId == proveedorId) puntaje += _bonusMismoProveedor;
    puntajes.add((id: p.id, puntaje: puntaje));
  }
  // Más parecido primero; a igual parecido, el id menor (para que sea determinista).
  puntajes.sort((a, b) => b.puntaje != a.puntaje ? b.puntaje.compareTo(a.puntaje) : a.id.compareTo(b.id));
  final alternativas = [for (final p in puntajes) if (p.puntaje >= _puntajeAlternativa) p.id].take(5).toList();
  if (puntajes.isEmpty) return const PropuestaDeVinculo(confianza: ConfianzaVinculo.ninguna);

  final mejor = puntajes.first;
  final segundo = puntajes.length > 1 ? puntajes[1] : null;
  final claro = mejor.puntaje >= _puntajeMinimo && (segundo == null || mejor.puntaje - segundo.puntaje >= _ventajaMinima);
  return PropuestaDeVinculo(
    productoId: claro ? mejor.id : null,
    confianza: claro ? ConfianzaVinculo.media : ConfianzaVinculo.ninguna,
    origen: claro ? OrigenVinculo.nombre : null,
    puntajePct: (mejor.puntaje.clamp(0, 1) * 100).round(),
    alternativas: alternativas,
  );
}

String _soloDigitos(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// Parecido de 0 a 1 entre las palabras de la factura y las del producto. Una palabra igual vale 1; una abreviatura (una es el
/// principio de la otra: "ALF" y "alfajor") vale 0,75; las que traen números (tamaños) tienen que ser iguales.
double _parecido(List<String> factura, List<String> producto) {
  if (factura.isEmpty || producto.isEmpty) return 0;
  final pares = <(double, int, int)>[];
  for (var i = 0; i < factura.length; i++) {
    for (var j = 0; j < producto.length; j++) {
      final w = _pesoDePalabra(factura[i], producto[j]);
      if (w > 0) pares.add((w, i, j));
    }
  }
  pares.sort((a, b) => b.$1.compareTo(a.$1));
  final usadasF = <int>{};
  final usadasP = <int>{};
  var suma = 0.0;
  for (final (w, i, j) in pares) {
    if (usadasF.contains(i) || usadasP.contains(j)) continue;
    usadasF.add(i);
    usadasP.add(j);
    suma += w;
  }
  final recall = suma / factura.length;
  final precision = suma / producto.length;
  if (recall + precision == 0) return 0;
  var puntaje = 2 * recall * precision / (recall + precision);

  // Un tamaño que contradice (la factura dice 70g y el producto 69g) casi seguro es otro producto.
  final tamanosF = {for (final t in factura) if (_tieneNumero(t)) t};
  final tamanosP = {for (final t in producto) if (_tieneNumero(t)) t};
  if (tamanosF.difference(tamanosP).isNotEmpty && tamanosP.difference(tamanosF).isNotEmpty) puntaje *= 0.75;
  return puntaje;
}

bool _tieneNumero(String s) => RegExp(r'\d').hasMatch(s);

double _pesoDePalabra(String a, String b) {
  if (a == b) return 1;
  if (_tieneNumero(a) || _tieneNumero(b)) return 0;
  final corta = a.length <= b.length ? a : b;
  final larga = a.length <= b.length ? b : a;
  return corta.length >= 2 && larga.startsWith(corta) ? 0.75 : 0;
}

/// Suma lo que sugirió una IA ([sugerencias]: posición de la línea → id de producto) a las [propuestas] que quedaron dudosas. Lo ya
/// vinculado con confianza alta (aprendido o código de barras) no se toca; una sugerencia a un producto que no está en [idsDelCatalogo]
/// se ignora (una IA puede inventar un id); y lo que sugiere la IA queda en confianza media: lo confirma el dueño.
List<PropuestaDeVinculo> conSugerenciasDeIa(
  List<PropuestaDeVinculo> propuestas,
  Map<int, int> sugerencias, {
  required Set<int> idsDelCatalogo,
}) {
  return [
    for (var i = 0; i < propuestas.length; i++)
      () {
        final p = propuestas[i];
        final id = sugerencias[i];
        if (p.confianza == ConfianzaVinculo.alta || id == null || !idsDelCatalogo.contains(id)) return p;
        return PropuestaDeVinculo(
          productoId: id,
          confianza: ConfianzaVinculo.media,
          origen: OrigenVinculo.ia,
          puntajePct: p.puntajePct,
          alternativas: [for (final a in p.alternativas) if (a != id) a],
          unidadesPorCantidad: p.unidadesPorCantidad,
        );
      }(),
  ];
}
