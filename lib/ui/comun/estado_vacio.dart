// Ícono en un círculo de color tenue + una línea de texto: el estado vacío
// único de la app (lista sin resultados, panel de detalle sin selección).
// `icono` es el único dato que cambia entre usos. Remake de la estética
// (El dueño, 2026-09-19): antes un ícono suelto en gris (fase 11) — ahora
// dentro de un círculo, mismo criterio que
// `lib/companion/tema/estado_vacio_companion.dart` ("íconos siempre dentro
// de un contenedor, nunca sueltos").

import 'package:flutter/material.dart';

import '../tema/tokens.dart';
import '../tema/iconos.dart';

class EstadoVacio extends StatelessWidget {
  const EstadoVacio({super.key, required this.mensaje, this.icono = IconosPlazoleta.inboxOutlined});

  final String mensaje;
  final IconData icono;

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
                color: colores.textoTenue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: IconoPlz(icono, size: 32, color: colores.textoTenue),
            ),
            const SizedBox(height: Espaciado.lg),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
            ),
          ],
        ),
      ),
    );
  }
}
