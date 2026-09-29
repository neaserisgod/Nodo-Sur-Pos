// Estado vacío propio de la companion — mismo rol que `EstadoVacio`
// (`lib/ui/comun/estado_vacio.dart`, compartido con el escritorio, sin
// tocar), pero con el ícono metido dentro de un círculo de color tenue en
// vez de suelto, acorde al estilo nuevo (íconos siempre dentro de un
// contenedor, nunca sueltos).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'tema_companion.dart';
import '../../ui/tema/iconos.dart';

class EstadoVacioCompanion extends StatelessWidget {
  const EstadoVacioCompanion({
    super.key,
    required this.mensaje,
    this.icono = IconosPlazoleta.inboxOutlined,
  });

  final String mensaje;
  final IconData icono;

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
                color: colores.textoTenue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 32, color: colores.textoTenue),
            ),
            const SizedBox(height: EspacioCompanion.lg),
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
