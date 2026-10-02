// Ícono dentro de un contenedor de color sólido — "solid icon containers",
// look "flat mobile": en vez de un ícono suelto en gris (como en el kit del
// escritorio), cada fila/acceso de la companion muestra su ícono en un
// cuadrado redondeado de color, para que la fila se reconozca de un vistazo
// por color, no solo por texto.

import 'package:flutter/material.dart';

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

  /// Halo neón (El dueño, 2026-09-19: "cyberpunk me vuela la gorra") — apagado
  /// por default: un ícono de lista corriente no necesita brillar, esto es
  /// para los accesos "importantes" de una grilla (`TarjetaAccion`), donde
  /// sí vale la pena que el color se note un poco más allá del cuadrado.
  final bool resplandor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanio,
      height: tamanio,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icono, color: color, size: tamanioIcono),
    );
  }
}
