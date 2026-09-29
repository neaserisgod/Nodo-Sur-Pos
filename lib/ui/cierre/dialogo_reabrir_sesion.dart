import 'package:flutter/material.dart';

import '../comun/botones.dart';
import '../comun/modal.dart';
import 'cierre_controlador.dart';

/// Regla 6: reabrir pide confirmación explícita, nunca es un clic accidental.
Future<void> mostrarDialogoReabrirSesion(BuildContext context, CierreControlador c) async {
  final confirmado = await mostrarModal<bool>(
    context,
    builder: (context) => Modal(
      titulo: '¿Reabrir la caja?',
      contenido: const Text(
        'Vas a poder seguir vendiendo bajo la misma sesión. El arqueo se vuelve '
        'a hacer desde cero la próxima vez que cierres.',
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
        BotonPrimario(texto: 'Reabrir', onPressed: () => Navigator.of(context).pop(true)),
      ],
    ),
  );
  if (confirmado == true) {
    await c.reabrir();
  }
}
