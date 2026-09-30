// Etiqueta a la izquierda, valor a la derecha, tocable — el patrón "lista de
// configuraciones con su valor, tocás y editás" que pedía la pantalla de
// Configuración de la companion (El dueño, 2026-09-19: "que se puedan
// modificar las reglas del negocio... desde el celular"). No existía en el
// kit de la companion (sí en el de escritorio, `lib/ui/comun/fila_dato.dart`,
// pero ese es de solo lectura, sin `onTap`) — pieza chica agregada al kit,
// mismo criterio de fase 13 en el escritorio: "si algo no se puede armar
// con el kit, se agrega una pieza al kit".

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'presionable.dart';
import 'superficie.dart';
import '../../ui/tema/iconos.dart';

class FilaDatoCompanion extends StatelessWidget {
  const FilaDatoCompanion({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.subtitulo,
    this.onTap,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;

  /// Segunda línea chica bajo la etiqueta — ej. "Ganancia sin revisar" en
  /// una fila de proveedor. Null si la fila no necesita una.
  final String? subtitulo;

  final VoidCallback? onTap;

  /// Tinte de acento en el valor — para lo que más importa resaltar sin
  /// sumar un color nuevo (ej. un medio de pago desactivado, en rojo).
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final fila = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: Theme.of(context).textTheme.bodyLarge),
                if (subtitulo != null)
                  Text(
                    subtitulo!,
                    style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Espaciado.md),
          Text(
            valor,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: destacado ? colores.error : null),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Espaciado.sm),
            Icon(IconosPlazoleta.chevronRight, color: colores.textoSecundario, size: 20),
          ],
        ],
      ),
    );
    return Superficie(
      padding: EdgeInsets.zero,
      child: onTap == null ? fila : Presionable(onTap: onTap, child: fila),
    );
  }
}
