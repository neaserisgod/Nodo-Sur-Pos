// Chip de selección única — mismo lenguaje visual que el resto de la
// companion (`Presionable` + colores del tema) en vez del `ChoiceChip` de
// Material de fábrica, que desentona con el resto de la pantalla. Antes
// vivía duplicado en `pantalla_precios.dart` (`_ChipFiltro`) y
// `hoja_edicion_masiva.dart` (`_chip`) — la misma pieza en dos archivos ya
// cuenta como el caso de Regla 3, así que se junta acá.
//
// Con resplandor neón al estar seleccionado (Bruno, 2026-09-19: "la
// estética japonesa cyberpunk me vuela la gorra") — apagado, no compite con
// las superficies "hero" que ya lo llevan.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'presionable.dart';
import 'resplandor.dart';

class ChipSeleccionable extends StatelessWidget {
  const ChipSeleccionable({
    super.key,
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Presionable(
      radio: 999,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: seleccionado ? colores.acento : colores.fondoBloque,
          borderRadius: BorderRadius.circular(999),
          border: seleccionado ? null : Border.all(color: colores.borde),
          boxShadow: seleccionado
              ? resplandorNeon(colores.acento, alpha: 0.35, radio: 12, offset: const Offset(0, 2))
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.md, vertical: Espaciado.sm),
        alignment: Alignment.center,
        child: Text(
          texto,
          style: TextStyle(
            color: seleccionado ? colores.acentoTexto : colores.textoSecundario,
            fontWeight: seleccionado ? Pesos.medium : Pesos.regular,
          ),
        ),
      ),
    );
  }
}
