// Interpretación y búsqueda del campo único de la pantalla de venta.
//
// Vive en `data/` (no en `domain/`) porque opera directamente sobre la fila
// `Producto` generada por drift — no es una regla de negocio en el sentido
// de fase 1, es la lógica de soporte de una pantalla concreta.
//
// El dueño, 2026-09-06: "si algo no hay stock, el producto no aparece en
// ventas" (versión inicial, a refinar después) — reemplaza lo que decía
// Regla 8 hasta acá ("el stock informa, nunca bloquea": un 0/negativo se
// vendía igual, solo se marcaba en rojo en el carrito). `tieneStock` es el
// único lugar que decide esto, para no repetir el criterio en cada lugar
// que filtra por stock.

import 'database.dart';
import 'normalizacion_texto.dart';

/// Resultado de interpretar lo que se escribió en el campo único.
class ConsultaBusqueda {
  /// Lo que hay que buscar por nombre (o comparar contra el código de
  /// barras), sin el prefijo de gramos si lo había.
  final String texto;

  /// No nulo si el texto tenía el patrón "200 queso barra" (Regla del campo
  /// único: un número al principio, seguido de espacio, son gramos de un
  /// pesable).
  final int? gramos;

  const ConsultaBusqueda({required this.texto, this.gramos});
}

final _patronGramos = RegExp(r'^(\d+)\s+(.+)$');

/// "Varios" no tiene stock real (Regla 5/9: monto suelto, no descuenta
/// stock) — siempre cuenta como que sí tiene. Un pesable mira
/// `stockGramos`, cualquier otro mira `stock`.
bool tieneStock(Producto producto) {
  if (producto.esVarios) return true;
  if (producto.esPesable) return (producto.stockGramos ?? 0) > 0;
  return producto.stock > 0;
}

ConsultaBusqueda interpretarTexto(String textoOriginal) {
  final recortado = textoOriginal.trim();
  final coincidencia = _patronGramos.firstMatch(recortado);
  if (coincidencia != null) {
    return ConsultaBusqueda(
      texto: coincidencia.group(2)!.trim(),
      gramos: int.parse(coincidencia.group(1)!),
    );
  }
  return ConsultaBusqueda(texto: recortado);
}

/// Busca en [catalogo] (ya cargado en memoria — ver por qué en
/// lib/ui/venta/venta_controlador.dart) según lo que hay en el campo único.
///
/// Un código de barras exacto gana solo, aunque el texto también matchee
/// nombres de otros productos: quien escaneó no quería elegir entre varios.
/// Con el patrón de gramos ("200 queso"), la búsqueda se restringe a
/// pesables — un texto así nunca puede ser un código de barras.
/// [exigirStock] en `false` (carga histórica, `repositorio_carga_historica.dart`):
/// una venta vieja no descuenta el stock de hoy (Convención de la carga
/// histórica), así que filtrar por stock actual escondería productos que sí
/// se vendieron en su momento pero están en 0 ahora por cualquier otro
/// motivo — el filtro de stock es una regla de la venta en vivo, no de
/// reconstruir el pasado.
/// [nombresNormalizados]/[codigosNormalizados] (por `producto.id`) evitan
/// recalcular `normalizarTexto` — 22 `replaceAll` sobre el string completo —
/// para cada producto del catálogo en cada tecla escrita: la pantalla de
/// venta (ruta caliente, ver `venta_controlador.dart`) los precalcula una
/// sola vez al cargar el catálogo; sin ellos (los otros tres llamadores:
/// carga histórica, editor de venta, servidor companion — ninguno corre por
/// tecla) se sigue calculando al vuelo como antes, mismo resultado.
List<Producto> buscarProductos({
  required List<Producto> catalogo,
  required String textoBuscado,
  int limite = 8,
  bool exigirStock = true,
  Map<int, String>? nombresNormalizados,
  Map<int, String>? codigosNormalizados,
}) {
  final consulta = interpretarTexto(textoBuscado);
  if (consulta.texto.isEmpty) return const [];

  final normalizado = normalizarTexto(consulta.texto);
  bool tieneStockSiExigido(Producto p) => !exigirStock || tieneStock(p);
  String codigoNormalizadoDe(Producto p) =>
      codigosNormalizados?[p.id] ?? normalizarTexto(p.codigoBarras ?? '');
  String nombreNormalizadoDe(Producto p) =>
      nombresNormalizados?[p.id] ?? normalizarTexto(p.nombre);

  if (consulta.gramos == null) {
    final porCodigo = catalogo
        .where(
          (p) =>
              p.activo &&
              tieneStockSiExigido(p) &&
              codigoNormalizadoDe(p) == normalizado,
        )
        .toList();
    if (porCodigo.isNotEmpty) return [porCodigo.first];
  }

  final candidatos = catalogo.where((p) {
    if (!p.activo) return false;
    if (!tieneStockSiExigido(p)) return false;
    if (consulta.gramos != null && !p.esPesable) return false;
    return nombreNormalizadoDe(p).contains(normalizado);
  }).toList();

  // "7 up" o "2 cocas" empiezan con un número pero no son gramos: si ningún pesable coincide, se busca el texto completo
  // entre todos los productos (el número queda como parte del nombre). Esa línea se agrega por unidad, sin gramos.
  if (candidatos.isEmpty && consulta.gramos != null) {
    final completo = normalizarTexto(textoBuscado.trim());
    return catalogo
        .where((p) => p.activo && tieneStockSiExigido(p) && nombreNormalizadoDe(p).contains(completo))
        .take(limite)
        .toList();
  }

  return candidatos.take(limite).toList();
}
