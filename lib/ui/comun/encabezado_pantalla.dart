// Encabezado de pantalla: el nombre de la pantalla en grande (liviano y
// apretado, como la web de Nodo Sur) con una línea de contexto debajo ("Hoy ·
// sábado 26 de septiembre"), y las acciones/selectores a la derecha. Pieza 2
// del kit — la usa `PantallaGestion` siempre.
//
// Rediseño "antigravity": vuelve el título grande (el menú de secciones de la
// navbar sigue mostrando dónde estás, pero cada pantalla se presenta con su
// nombre como en los mocks).

import 'package:flutter/material.dart';


class EncabezadoPantalla extends StatelessWidget {
  const EncabezadoPantalla({super.key, required this.titulo, this.subtitulo, this.accion});

  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: titulo,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.displayLarge?.copyWith(letterSpacing: -2.4),
                  ),
                ),
                // Sin subtítulo (rediseño v4, 2026-10-05: "eliminá las redundancias"): el título y el contenido ya dicen de
                // qué es la pantalla. [subtitulo] queda en la firma para no tocar a quien lo pasa, pero no se dibuja.
              ],
            ),
          ),
          ?accion,
        ],
      ),
    );
  }
}
