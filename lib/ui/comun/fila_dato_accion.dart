// Etiqueta a la izquierda, valor a la derecha, tocable — análogo de
// escritorio de `FilaDatoCompanion`
// (`lib/companion/tema/fila_dato_companion.dart`). Pieza nueva, opt-in: el
// patrón "tocar una fila abre su edición en un modal" no reemplaza a
// `FilaDato` (lectura pura) en todos lados — Configuración es el primer
// adoptante natural (remake de la estética, Bruno 2026-09-19).

import 'package:flutter/material.dart';

import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../tema/iconos.dart';

class FilaDatoAccion extends StatelessWidget {
  const FilaDatoAccion({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.subtitulo,
    this.onTap,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;

  /// Segunda línea chica bajo la etiqueta. Null si la fila no necesita una.
  final String? subtitulo;

  final VoidCallback? onTap;

  /// Tinte de acento en el valor — para lo que más importa resaltar (ej. un
  /// medio de pago desactivado, en rojo).
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
                Text(etiqueta, style: Theme.of(context).textTheme.bodyMedium),
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
