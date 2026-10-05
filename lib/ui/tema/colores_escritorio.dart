// Paleta de la app — escritorio y companion comparten estos mismos valores
// (`colores_companion.dart` los reexporta: una sola paleta, Regla 3).
//
// 2026-10-05 (mock "Nodo Sur", decisión del dueño): los valores son los mismos del celular (`colores_companion.dart`).
// En oscuro el acento pasa a ser el azul de marca `#2F5BE8`; en claro sigue la tinta.
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
  borde: Color(0xFFE1E4EA),
  textoPrimario: Color(0xFF121317),
  textoSecundario: Color(0xFF566070),
  textoTenue: Color(0xFF566070),
  acento: Color(0xFF121317),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFA4231B),
  errorTexto: Color(0xFFFFFFFF),
);

const coloresEscritorioOscuro = ColoresPlazoleta(
  fondo: Color(0xFF0E0F12),
  fondoBloque: Color(0xFF14161C),
  borde: Color(0xFF2A2E38),
  textoPrimario: Color(0xFFEEF0F4),
  textoSecundario: Color(0xFFA0A8B6),
  textoTenue: Color(0xFFA0A8B6),
  acento: Color(0xFF2F5BE8),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFFF918A),
  errorTexto: Color(0xFF3A1613),
);
