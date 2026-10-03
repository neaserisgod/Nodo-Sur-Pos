// Chip de selección única — puerto de
// `lib/companion/tema/chip_seleccionable.dart`, mismo lenguaje visual
// (`Presionable` + colores del tema) en vez del `ChoiceChip` de Material de
// fábrica. Con resplandor neón al estar seleccionado.

import 'package:flutter/material.dart';

import 'presionable.dart';
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
        ),
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.md),
        constraints: const BoxConstraints(minHeight: Medidas.alturaControl),
        alignment: Alignment.center,
        child: Text(
          texto,
          style: TextStyle(
            color: seleccionado ? colores.acentoTexto : colores.textoPrimario,
            fontWeight: seleccionado ? Pesos.medium : Pesos.regular,
          ),
        ),
      ),
    );
  }
}
