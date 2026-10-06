// Esc y la "x" de la pestaña cancelan la venta entera sin preguntar, así que lo
// que se pierde se puede recuperar unos segundos desde el aviso de arriba (v4:
// los avisos salen arriba y no tapan el cobro, regla dura de Venta, `CLAUDE.md`).

import 'package:flutter/material.dart';

import '../comun/aviso_superior.dart';
import 'venta_controlador.dart';

void cancelarVentaConDeshacer(BuildContext context, VentaControlador c) {
  final foto = c.fotoDeLaVentaActiva();
  c.cancelarVenta();
  if (foto.estaVacio) return;
  mostrarAviso(context, 'Cancelaste la venta', textoAccion: 'Deshacer', alAccionar: () => c.reabrirVenta(foto));
}
