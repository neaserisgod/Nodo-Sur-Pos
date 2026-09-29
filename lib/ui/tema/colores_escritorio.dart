// Paleta de la app — escritorio y companion comparten estos mismos valores
// (`colores_companion.dart` los reexporta: una sola paleta, Regla 3).
//
// "Lenguaje de diseño" (Bruno, 2026-09-26, carpeta de mocks en la raíz del
// repo, "medio inspiración"): reemplaza el "dark glass premium" verde-
// azulado por un claro plano estilo Google — canvas gris azulado, tarjetas
// blancas sin sombra, un acento azul. El claro sale tal cual de los tokens
// del LEEME de esa carpeta; el oscuro no existe en los mocks y se derivó a
// mano con el mismo criterio (Bruno eligió mantenerlo): mismo hue de
// acento, aclarado para que tenga contraste sobre fondo oscuro, y nunca
// negro puro de fondo ni blanco puro de texto (CLAUDE.md, contraste medido).

import 'package:flutter/material.dart';

import 'tokens.dart';

const coloresEscritorioClaro = ColoresPlazoleta(
  fondo: Color(0xFFF0F4F9),
  fondoBloque: Color(0xFFFFFFFF),
  // Borde de controles (OutlinedButton, riel del Switch): el gris de los
  // contornos del mock, no el de los separadores (#E3E3E3) — un borde que
  // no se ve no cumple su función de señalar "esto se toca".
  borde: Color(0xFFC4C7C5),
  textoPrimario: Color(0xFF1F1F1F),
  textoSecundario: Color(0xFF444746),
  textoTenue: Color(0xFF5E5E5E),
  acento: Color(0xFF0B57D0),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFB3261E),
  errorTexto: Color(0xFFFFFFFF),
);

const coloresEscritorioOscuro = ColoresPlazoleta(
  fondo: Color(0xFF111318),
  fondoBloque: Color(0xFF1D2026),
  borde: Color(0xFF5C5F63),
  textoPrimario: Color(0xFFE6E8EB),
  textoSecundario: Color(0xFFC4C7C5),
  textoTenue: Color(0xFF9A9D9F),
  acento: Color(0xFFA8C7FA),
  acentoTexto: Color(0xFF062E6F),
  error: Color(0xFFF2B8B5),
  errorTexto: Color(0xFF601410),
);
