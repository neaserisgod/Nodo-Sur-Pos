// Encabezado de pantalla: una línea de contexto a la izquierda ("Hoy ·
// sábado 26 de septiembre") y las acciones/selectores a la derecha. Pieza 2
// del kit — la usa `PantallaGestion` siempre.
//
// "Lenguaje de diseño" (Bruno, 2026-09-26): el título grande se sacó de
// acá. En los mocks el nombre de la pantalla ES el botón del menú de
// secciones (navbar), así que repetirlo abajo en letra grande era decir lo
// mismo dos veces; `titulo` queda para la semántica (lectores de pantalla)
// y para las pantallas que todavía no pasan un subtítulo.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';

class EncabezadoPantalla extends StatelessWidget {
  const EncabezadoPantalla({super.key, required this.titulo, this.subtitulo, this.accion});

  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: titulo,
      child: Row(
        children: [
          Expanded(
            child: Text(
              subtitulo ?? '',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario),
            ),
          ),
          ?accion,
        ],
      ),
    );
  }
}
