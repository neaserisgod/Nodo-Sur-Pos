// Colores de los cuatro medios de pago — dato FIJO de Venta (CLAUDE.md:
// "Fijo en el código... atajos de teclado"), no una fórmula que otra
// pantalla necesite. `colorCategoria`/`BarraCategoria` (el color por rubro
// de producto) se mudaron a `ui/comun/color_categoria.dart` en el rediseño
// de Proveedores 2026-09-25 (quinta pasada) — Proveedores también los
// necesita ahora, y esto no era un lugar compartido.
//
// Reconciliado en el remake de estética (El dueño, 2026-09-19: "la pantalla de
// ventas se adapte también") — los cuatro colores son los mismos que ya usa
// `AcentosPlazoleta` (`lib/ui/tema/acentos.dart`, portados con fidelidad
// completa de la companion) para QR/Débito/Mixto, y el acento único de la
// app para Efectivo — mismo criterio que ya usa la companion
// (`colores_companion.dart`: "Efectivo comparte el verde-azulado principal:
// es el medio más usado, tiene sentido que sea 'el' acento").

import 'package:flutter/material.dart';

import '../tema/acentos.dart';

/// Los cuatro medios de pago son datos FIJOS de la app (CLAUDE.md: "Fijo en
/// el código... atajos de teclado"), así que cada uno tiene un color propio
/// y fijo — a diferencia de las categorías (dato de negocio configurable,
/// `ui/comun/color_categoria.dart`), acá no hace falta ningún cálculo.
abstract final class ColorMedioPago {
  // Naranja de efectivo, el mismo del resto de la app ("Lenguaje de
  // diseño", 2026-09-26) — antes era el acento general.
  static Color efectivo(BuildContext context) => context.acentosPlazoleta.dinero;

  static Color qr(BuildContext context) => context.acentosPlazoleta.qr;

  static Color debito(BuildContext context) => context.acentosPlazoleta.debito;

  static Color mixto(BuildContext context) => context.acentosPlazoleta.mixto;
}
