// La unidad visual del estilo bento (fase 11): un bloque de esquinas
// redondeadas y fondo apenas más claro que el canvas, sin borde y sin
// sombra — la jerarquía se hace solo con esa diferencia de color. Es el
// reemplazo directo de `Card` en toda la app: `Card` trae elevación (y con
// ella, sombra) por defecto, que el hardware (PC de 2008) no puede pagar
// repetida en cada bloque de una pantalla.

import 'package:flutter/material.dart';

import 'tokens.dart';

class Bloque extends StatelessWidget {
  const Bloque({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(Bento.paddingBloque),
    this.colorFilete,
  });

  final Widget child;

  /// Por defecto `context.colores.fondoBloque`. Los bloques son escala de
  /// grises siempre — el único color con significado (`colores.acento`) se
  /// usa en el texto o en un resalte puntual, nunca llenando un bloque
  /// entero.
  final Color? color;

  final EdgeInsetsGeometry padding;

  /// Filete superior de 3px, opcional — nulo en toda la app salvo donde se
  /// pida explícitamente ("Bento con carácter", venta, Bruno 2026-09-16:
  /// "dejemos el monocromo, démosle vida"). No cambia el radio ni el
  /// padding del bloque, así que no rompe la alineación con bloques
  /// vecinos que no lo usan.
  final Color? colorFilete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.colores.fondoBloque,
        borderRadius: BorderRadius.circular(Bento.radio),
        border: colorFilete == null
            ? null
            : Border(top: BorderSide(color: colorFilete!, width: 3)),
      ),
      child: child,
    );
  }
}
