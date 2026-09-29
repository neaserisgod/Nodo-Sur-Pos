// Chip de selección única — puerto de
// `lib/companion/tema/chip_seleccionable.dart`, mismo lenguaje visual
// (`Presionable` + colores del tema) en vez del `ChoiceChip` de Material de
// fábrica. Con resplandor neón al estar seleccionado.

import 'package:flutter/material.dart';

import 'presionable.dart';
import 'resplandor.dart';
import 'tokens.dart';

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
