// Esc y la "x" de la pestaña cancelan la venta entera sin preguntar, así que lo
// que se pierde se puede recuperar unos segundos desde un snackbar. Flota a la
// izquierda para no tapar el cobro (regla dura de Venta, `CLAUDE.md`).

import 'package:flutter/material.dart';

import '../tema/tokens.dart';
import 'venta_controlador.dart';

void cancelarVentaConDeshacer(BuildContext context, VentaControlador c) {
  final foto = c.fotoDeLaVentaActiva();
  c.cancelarVenta();
  if (foto.estaVacio) return;
  final mensajero = ScaffoldMessenger.of(context);
  mensajero.clearSnackBars();
  mensajero.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(
        left: Espaciado.lg,
        right: Medidas.anchoPanelCobroVenta + Espaciado.lg,
        bottom: Espaciado.lg,
      ),
      duration: const Duration(seconds: 5),
      content: const Text('Cancelaste la venta'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => c.reabrirVenta(foto)),
    ),
  );
}
