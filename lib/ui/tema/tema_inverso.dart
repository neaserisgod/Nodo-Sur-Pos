// Contenido sobre una superficie pintada con el acento (la fila elegida, la
// pastilla activa): en el rediseño "antigravity" lo elegido se marca con un
// bloque de tinta (negro en claro, blanco en oscuro), así que el texto y los
// íconos de adentro tienen que invertirse. Este widget reemplaza el tema de
// su subárbol por uno con los colores invertidos; si [activo] es falso deja
// el hijo tal cual.

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Colores y estilos de texto para armar una fila que puede estar elegida:
/// con [activo] salen ya invertidos (los `TextStyle` llevan el color
/// "horneado", así que no alcanza con envolver el subárbol).
({ColoresPlazoleta colores, TextTheme textTheme}) coloresDeFila(BuildContext context, bool activo) {
  final base = Theme.of(context);
  final colores = context.colores;
  if (!activo) return (colores: colores, textTheme: base.textTheme);
  final sobre = colores.acentoTexto;
  final invertidos = colores.copyWith(
    textoPrimario: sobre,
    textoSecundario: sobre.withValues(alpha: 0.78),
    textoTenue: sobre.withValues(alpha: 0.6),
    borde: sobre.withValues(alpha: 0.24),
  );
  return (colores: invertidos, textTheme: base.textTheme.apply(bodyColor: sobre, displayColor: sobre));
}

class TemaInverso extends StatelessWidget {
  const TemaInverso({super.key, required this.activo, required this.child, this.invertirAcento = false});

  final bool activo;

  /// También intercambia el acento con su texto (para dibujar con el acento
  /// sobre un bloque oscuro, ej. las barras de un gráfico).
  final bool invertirAcento;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!activo) return child;
    final base = Theme.of(context);
    final colores = context.colores;
    final sobre = colores.acentoTexto;
    final invertidos = colores.copyWith(
      textoPrimario: sobre,
      textoSecundario: sobre.withValues(alpha: 0.78),
      textoTenue: sobre.withValues(alpha: 0.6),
      borde: sobre.withValues(alpha: 0.24),
      acento: invertirAcento ? sobre : colores.acento,
      acentoTexto: invertirAcento ? colores.acento : colores.acentoTexto,
    );
    final extensiones = [
      for (final e in base.extensions.values)
        if (e is! ColoresPlazoleta) e,
      invertidos,
    ];
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(bodyColor: sobre, displayColor: sobre),
        iconTheme: IconThemeData(color: sobre),
        extensions: extensiones,
      ),
      child: child,
    );
  }
}
