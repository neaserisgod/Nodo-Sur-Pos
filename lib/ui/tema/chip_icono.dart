// Ícono dentro de un contenedor de color sólido — puerto de
// `lib/companion/tema/chip_icono.dart`. En vez de un ícono suelto en gris
// (el lenguaje de fase 11), cada fila/acceso muestra su ícono en un
// cuadrado redondeado de color, para reconocerse de un vistazo por color,
// no solo por texto.

import 'package:flutter/material.dart';
import 'iconos.dart';

import 'resplandor.dart';

class ChipIcono extends StatelessWidget {
  const ChipIcono({
    super.key,
    required this.icono,
    required this.color,
    this.tamanio = 44,
    this.tamanioIcono = 22,
    this.resplandor = false,
  });

  final IconData icono;
  final Color color;
  final double tamanio;
  final double tamanioIcono;

  /// Halo neón — apagado por default: un ícono de lista corriente no
  /// necesita brillar, esto es para los accesos "importantes" de una
  /// grilla (`TarjetaAccion`), donde sí vale la pena que el color se note
  /// un poco más allá del cuadrado.
  final bool resplandor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanio,
      height: tamanio,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(tamanio * 0.32),
        boxShadow: resplandor ? resplandorNeon(color, alpha: 0.35, radio: 14, offset: const Offset(0, 3)) : null,
      ),
      child: IconoPlz(icono, color: color, size: tamanioIcono),
    );
  }
}
