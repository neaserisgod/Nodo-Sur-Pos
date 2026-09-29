// "Bento con carácter" (Bruno, 2026-09-16: "dejemos el monocromo... démosle
// vida" — pensado primero para Venta, cada rubro con su propio color) —
// compartido desde el rediseño de Proveedores 2026-09-25 (quinta pasada,
// Bruno: "seguro que rediseñaste? lo veo practicamente igual" — la tabla de
// productos no tenía NADA de este lenguaje todavía). Antes vivía en
// `ui/venta/color_categoria.dart` junto a `ColorMedioPago` (que sigue ahí:
// es un dato fijo de Venta, no una fórmula que otra pantalla necesite).

import 'package:flutter/material.dart';

/// Paleta categórica de 8 colores, un tono por posición — recorrida por
/// posición (`categoriaId % paleta.length`), nunca por nombre: la categoría
/// es un dato configurable (Configuración → Categorías), nadie eligió a
/// mano "bebidas = azul". Mismo color siempre para la misma categoría,
/// distinto entre categorías vecinas, sin mantenimiento cuando Bruno crea
/// una nueva.
const List<Color> _paletaCategoriaClaro = [
  Color(0xFF2E6FA3), // azul
  Color(0xFF3E7A32), // verde
  Color(0xFFB8502E), // coral
  Color(0xFF6B4FA0), // violeta
  Color(0xFFA07C1E), // mostaza
  Color(0xFF1E7A72), // turquesa
  Color(0xFFA04670), // rosa
  Color(0xFF5B6B8C), // pizarra
];

const List<Color> _paletaCategoriaOscuro = [
  Color(0xFF4FA3E0),
  Color(0xFF5FA84A),
  Color(0xFFD65B3B),
  Color(0xFF8B6ADB),
  Color(0xFFC79A3A),
  Color(0xFF35B0A5),
  Color(0xFFC26B95),
  Color(0xFF8090B0),
];

/// `null` sin categoría cargada (`Producto.categoriaId`/`ProductoDeProveedor.
/// categoriaId` son nullable) — el llamador decide qué hacer (típicamente,
/// no dibujar la barra en vez de inventar un color "sin categoría").
Color? colorCategoria(BuildContext context, int? categoriaId) {
  if (categoriaId == null) return null;
  final paleta = Theme.of(context).brightness == Brightness.dark
      ? _paletaCategoriaOscuro
      : _paletaCategoriaClaro;
  return paleta[categoriaId % paleta.length];
}

/// La barra de acento que identifica el rubro de una fila (carrito,
/// resultado de búsqueda, tabla de productos de Proveedores) — una barra
/// vertical en píldora se lee como acento de tarjeta, no como un simple
/// bullet de lista. Mismo tamaño en todos los lugares que la usan. No se
/// dibuja nada si `color` es null (sin categoría cargada).
class BarraCategoria extends StatelessWidget {
  const BarraCategoria({super.key, required this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (color == null) return const SizedBox.shrink();
    return Container(
      width: 3,
      height: 18,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
    );
  }
}
