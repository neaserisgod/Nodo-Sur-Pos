// Tipografía del mock v4: Figtree con los pesos exactos del CSS (450, 550... con la variable `FigtreeV`), tracking en
// em como el CSS (se pasa a px multiplicando por el tamaño) y números tabulares donde el mock los pide (`.num`).

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';

const familiaMock = 'FigtreeV';

/// Un estilo del mock: `estilo(17, 600)` = `font-size:17px;font-weight:600`. [em] es el `letter-spacing` en em; [alto]
/// el `line-height`; [num] activa las cifras tabulares.
TextStyle estilo(
  double tamanio,
  double peso, {
  Color? color,
  double em = 0,
  double? alto,
  bool num = false,
  TextDecoration? decoracion,
}) {
  return TextStyle(
    fontFamily: familiaMock,
    fontSize: tamanio,
    // `fontWeight` además de la variación: si algún día falta la fuente variable, el sistema elige el peso más cercano.
    fontWeight: _pesoCercano(peso),
    fontVariations: [FontVariation.weight(peso)],
    letterSpacing: em * tamanio,
    height: alto,
    color: color,
    decoration: decoracion,
    fontFeatures: num ? const [FontFeature.tabularFigures()] : null,
  );
}

FontWeight _pesoCercano(double peso) {
  final i = ((peso / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[i];
}

/// Los roles con nombre del CSS (`.h1`, `.h2`, `.h3`, `.lead`, `.fig`...).
abstract final class Tipos {
  static TextStyle h1(Color c, {double tamanio = 48}) => estilo(tamanio, 450, color: c, em: -.045, alto: 1.05);
  static TextStyle h2(Color c, {double tamanio = 34}) => estilo(tamanio, 450, color: c, em: -.045, alto: 1.04);
  static TextStyle h3(Color c) => estilo(28, 450, color: c, em: -.035, alto: 1.1);
  static TextStyle lead(Color c) => estilo(21, 400, color: c, alto: 1.5);

  /// `.fig`: la cifra grande de una tarjeta.
  static TextStyle fig(Color c, {double tamanio = 44}) => estilo(tamanio, 450, color: c, em: -.055, alto: 1, num: true);

  /// `.kbd`: el atajo impreso en un botón.
  static TextStyle kbd(Color c, {double tamanio = 12}) => estilo(tamanio, 600, color: c, em: .02, alto: 1.3);
}

/// La plata como la escribe el mock: `$ 16.300`. Única puerta del kit a `formatearARS` (Regla 3).
String pesos(int centavos) => formatearARS(centavos, separado: true);

/// Con signo explícito adelante: `+$ 50`, `−$ 3.000` (el mock usa el menos tipográfico en descuentos y gastos).
String pesosConSigno(int centavos, {bool menosTipografico = true}) {
  if (centavos > 0) return '+${pesos(centavos)}';
  if (centavos < 0) return '${menosTipografico ? '−' : '-'}${pesos(-centavos)}';
  return pesos(0);
}

/// Decoración de un campo del mock: sin bordes, sin relleno y sin el padding del tema (el dibujo lo pone el contenedor).
InputDecoration decoracionSinBorde(String? pista, TextStyle estiloPista) => InputDecoration(
      hintText: pista,
      hintStyle: estiloPista,
      isDense: true,
      isCollapsed: true,
      filled: false,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );
