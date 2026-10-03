// Paleta de la app — escritorio y companion comparten estos mismos valores
// (`colores_companion.dart` los reexporta: una sola paleta, Regla 3).
//
// Rediseño "antigravity" (mismo que la web de Nodo Sur y la companion):
// blanco de fondo, bloques gris muy claro, tinta casi negra como acento (los
// botones principales son píldoras negras) y color solo donde significa algo
// (medios de pago, ganancia, alertas). Misma paleta que
// `lib/companion/tema/colores_companion.dart`: una sola identidad visual en
// escritorio y celular. En oscuro, negro puro de fondo.

import 'package:flutter/material.dart';

import 'tokens.dart';

const coloresEscritorioClaro = ColoresPlazoleta(
  fondo: Color(0xFFFFFFFF),
  fondoBloque: Color(0xFFF3F4F7),
  borde: Color(0xFFD5D8DF),
  textoPrimario: Color(0xFF121317),
  textoSecundario: Color(0xFF566070),
  textoTenue: Color(0xFF6B7385),
  acento: Color(0xFF121317),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFC5221F),
  errorTexto: Color(0xFFFFFFFF),
);

const coloresEscritorioOscuro = ColoresPlazoleta(
  fondo: Color(0xFF0E0F12),
  fondoBloque: Color(0xFF14161C),
  borde: Color(0xFF2A2D36),
  textoPrimario: Color(0xFFF4F5F7),
  textoSecundario: Color(0xFFA9B0BF),
  textoTenue: Color(0xFF7D8597),
  acento: Color(0xFFFFFFFF),
  acentoTexto: Color(0xFF121317),
  error: Color(0xFFFF8A80),
  errorTexto: Color(0xFF3B0A08),
);
