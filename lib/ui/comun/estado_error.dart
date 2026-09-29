// Mismo lenguaje visual que `EstadoVacio` (ícono en círculo + texto), pero
// con un botón sólido para reintentar sin salir de la pantalla — antes cada
// carga inicial fallida dejaba a la companion en un spinner infinito o un
// mensaje mudo, sin forma de reintentar salvo salir y volver a entrar
// (Bruno, 2026-09-17: "hacelo de una vez bien" tras varios incidentes donde
// no se podía distinguir "cargando" de "roto"). Remake de la estética
// (2026-09-19): mismo criterio que
// `lib/companion/tema/estado_error_companion.dart` — ícono con tinte del
// color de error, botón sólido en vez de `OutlinedButton`.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';
import '../tema/iconos.dart';

class EstadoError extends StatelessWidget {
  const EstadoError({
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
        padding: const EdgeInsets.all(Espaciado.xl),
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
            const SizedBox(height: Espaciado.lg),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.lg),
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
