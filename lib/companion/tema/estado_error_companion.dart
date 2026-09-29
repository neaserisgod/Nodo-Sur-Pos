// Estado de error propio de la companion, con botón de reintentar — mismo
// rol que `EstadoError` (`lib/ui/comun/estado_error.dart`, compartido con
// el escritorio, sin tocar), con el ícono dentro de un círculo de color
// (tinte del color de error) y un botón sólido en vez de `OutlinedButton`,
// acorde al estilo nuevo.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'tema_companion.dart';
import '../../ui/tema/iconos.dart';

class EstadoErrorCompanion extends StatelessWidget {
  const EstadoErrorCompanion({
    super.key,
    required this.mensaje,
    required this.onReintentar,
  });

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EspacioCompanion.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colores.error.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(IconosPlazoleta.errorOutline, size: 32, color: colores.error),
            ),
            const SizedBox(height: EspacioCompanion.lg),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
            ),
            const SizedBox(height: EspacioCompanion.lg),
            FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(IconosPlazoleta.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
