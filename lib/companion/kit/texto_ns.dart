// Escala tipográfica del mock (docs/01 §1.1): Figtree, títulos y cifras en
// "peso 450" con tracking negativo y números tabulares. Figtree del mock se
// publica en 400/500/600/700, así que el navegador dibuja el 450 como 500:
// acá igual (`peso450` = w500), que es la única desviación que permite el doc.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart' show familiaTipografica;

const FontWeight peso450 = FontWeight.w500;

/// Estilo de texto del kit. [track] va en em (como en el CSS del mock) y
/// [altura] es el interlineado relativo al tamaño.
TextStyle estiloNs(
  double tamanio, {
  FontWeight peso = FontWeight.w400,
  double track = 0,
  double? altura,
  Color? color,
  bool tabular = false,
  TextDecoration? decoracion,
}) {
  return TextStyle(
    fontFamily: familiaTipografica,
    fontSize: tamanio,
    fontWeight: peso,
    letterSpacing: tamanio * track,
    height: altura,
    color: color,
    decoration: decoracion,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// Título o cifra grande (peso 450).
TextStyle tituloNs(double tamanio, {double track = -0.055, double altura = 1.0, Color? color}) =>
    estiloNs(tamanio, peso: peso450, track: track, altura: altura, color: color, tabular: true);

/// Rótulo de sección: 14/700, mayúsculas, +0.04em.
TextStyle seccionNs(Color mute) => estiloNs(14, peso: FontWeight.w700, track: 0.04, color: mute);

/// Formatea el texto de una sección en mayúsculas (el CSS usa `text-transform`).
String mayusculasNs(String t) => t.toUpperCase();
