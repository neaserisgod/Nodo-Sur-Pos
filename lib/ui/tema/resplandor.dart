// Resplandor neón — apagado en el "Lenguaje de diseño" (El dueño, 2026-09-26):
// el lenguaje nuevo es plano, sin halos de color. La función se queda (y
// devuelve una lista vacía) para que los llamadores no cambien: si algún
// día vuelve un halo, se prende de nuevo acá y en un solo lugar (Regla 3).

import 'package:flutter/material.dart';

List<BoxShadow> resplandorNeon(
  Color color, {
  double alpha = 0.45,
  double radio = 20,
  double dispersion = 0,
  Offset offset = const Offset(0, 6),
}) => const [];
