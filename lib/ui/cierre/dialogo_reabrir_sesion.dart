import 'package:flutter/material.dart';

import '../kit/kit.dart';
import 'cierre_controlador.dart';

/// Regla 6: reabrir pide confirmación explícita, nunca es un clic accidental.
Future<void> mostrarDialogoReabrirSesion(BuildContext context, CierreControlador c) async {
  final confirmado = await mostrarModalMock<bool>(
    context,
    builder: (context) => ModalMock(
      titulo: '¿Reabrir la caja?',
      subtitulo: 'Vas a poder seguir vendiendo bajo la misma sesión. El arqueo se vuelve a hacer desde cero la próxima '
          'vez que cierres.',
      ancho: AnchoModal.angosto,
      cuerpo: const [],
      pieEnFila: true,
      pie: [
        Btn('Cancelar', variante: VarBtn.ton, onTap: () => Navigator.of(context).pop(false)),
        Btn('Reabrir', variante: VarBtn.dark, onTap: () => Navigator.of(context).pop(true)),
      ],
    ),
  );
  if (confirmado == true) {
    await c.reabrir();
  }
}
