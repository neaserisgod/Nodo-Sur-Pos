// Mensaje de error de una acción, pegado al botón que lo causó. Reemplaza el
// `Text` rojo suelto que cada pantalla armaba a mano: con ícono para no
// depender solo del color, y anunciado por el lector de pantalla apenas
// aparece (`liveRegion`), que un texto común no hace.
//
// Es para errores de ACCIÓN (guardar, cobrar, abrir caja). Un error al CARGAR
// una pantalla va con `EstadoError`, que ofrece reintentar; el
// `SnackBar` queda para confirmaciones, porque desaparece solo.

import 'package:flutter/material.dart';

import '../../ui/tema/iconos.dart';
import '../../ui/tema/tokens.dart';

class ErrorEnLinea extends StatelessWidget {
  const ErrorEnLinea(this.mensaje, {super.key});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(IconosPlazoleta.errorOutline, size: 18, color: colores.error),
          ),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(mensaje, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.error)),
          ),
        ],
      ),
    );
  }
}
