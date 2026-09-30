// Acciones que necesitan un BuildContext (para abrir un diálogo) además del
// controlador. Compartidas entre los widgets de columna y el manejador
// global de teclas de pantalla_venta.dart, para no duplicar la lógica.

import 'package:flutter/widgets.dart';

import '../../domain/medio_pago.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import 'dialogo_cobro_posnet.dart';
import 'dialogo_mixto.dart';
import 'dialogo_monto_varios.dart';
import 'venta_controlador.dart';

/// Única fuente de verdad de las teclas que `Alt` + tecla ya usa para una
/// acción fija de la pantalla de venta — el handler de teclado
/// (`pantalla_venta.dart`) es el único lector. Claves en minúscula,
/// comparar siempre con `.toLowerCase()`.
const Map<String, String> teclasReservadas = {
  'e': 'efectivo',
  // Fase 12: QR y Débito, canal de cobro por terminal Point — elige el
  // canal nada más (El dueño, 2026-09-08: volvió a ser de dos pasos, ver 'm'
  // abajo). "Cobrar" (Enter con el campo vacío, o el botón) recién ahí
  // abre el diálogo que manda la orden.
  'q': 'QR',
  'd': 'débito',
  'x': 'pago mixto',
  // El dueño, 2026-09-08: "necesito cobro manual en el desktop, ya que al
  // poner los atajos rápidos no hay más modal para seleccionarlo" — con
  // QR/Débito ya elegido, cobra directo sin pasar por la terminal Point
  // (mismo criterio que "Cobrar a mano" del diálogo de Point cuando
  // falla, pero elegible desde el arranque, no solo como resguardo).
  'm': 'cobro manual (sin terminal)',
  'v': 'Varios',
  'c': 'vuelto',
  '-': 'gasto rápido',
  // El dueño, 2026-09-13: "un botón de ingreso de dinero" — letra, no símbolo
  // ('+' con Alt depende del layout de teclado y si hace falta Shift para
  // llegar a esa tecla; una letra no tiene esa ambigüedad).
  'i': 'ingreso rápido',
  // El dueño, 2026-09-29: más de una venta a la vez. Alt+N abre una venta
  // nueva sin perder la actual; Alt+S pasa a la siguiente abierta.
  'n': 'nueva venta',
  's': 'siguiente venta abierta',
};

/// Alt+X: abre el campo aparte para la parte en efectivo de un pago mixto.
/// No reutiliza el campo único — un escaneo accidental mientras se carga el
/// monto no debe leerse como plata. El foco YA NO vuelve solo al campo
/// único al cerrarse el diálogo (El dueño, 2026-09-16: "dejar de robar el
/// foco al hacer otra cosa") — se queda donde haya quedado.
Future<void> abrirMixto(BuildContext context, VentaControlador c) async {
  if (c.carrito.isEmpty) return;
  c.elegirMedio(ComposicionPago.mixto);
  final total = c.resultado!.totalCentavos;
  final confirmado = await mostrarDialogoMixto(context, totalCentavos: total);
  if (confirmado != null) {
    c.confirmarMixto(confirmado.monto, canalResto: confirmado.canal);
  }
}

/// Alt+V: "Varios" es un monto suelto, se pregunta en un diálogo aparte por
/// la misma razón que mixto — nadie puede escribir un monto en el campo
/// único sin arriesgarse a que un escaneo lo pise. Mismo criterio que
/// `abrirMixto`: el foco no vuelve solo al cerrarse.
Future<void> agregarVarios(BuildContext context, VentaControlador c) async {
  final varios = c.productoVarios;
  if (varios == null) return;
  final monto = await mostrarDialogoMontoVarios(context);
  if (monto != null) c.agregarProducto(varios, montoVariosCentavos: monto);
}

/// Cobra la venta actual — o, si el medio elegido tiene un canal de la
/// terminal Point (QR/Débito, o el resto de un mixto, Fase 12), abre el
/// diálogo que dispara la orden y espera el resultado antes de grabar
/// nada. Mismo camino desde el botón "Cobrar" y desde Enter con el campo
/// vacío — las dos formas de cobrar siempre terminan en el mismo lugar,
/// esto no es la excepción.
Future<void> cobrarOAbrirPosnet(
  BuildContext context,
  VentaControlador c,
) async {
  // El carrito vacío se deja pasar a `cobrarActual()` sin más: ese es el
  // camino que ya sabe que "Enter con nada para cobrar" no es un error
  // (ver avisoCobro) — abrir el diálogo de posnet para una venta vacía no
  // tendría sentido.
  // Sin el módulo Point no hay terminal: QR y Débito se cobran a mano, directo (el mismo camino que "Cobrar a mano").
  if (c.carrito.isNotEmpty && c.canalElegido != null && moduloActivo(Modulo.cobroPoint)) {
    await mostrarDialogoCobroPosnet(context, controlador: c);
  } else {
    await c.cobrarActual();
  }
}

/// Alt+M, o el botón "Cobrar a mano (sin terminal)": cobra directo, sin
/// tocar la terminal Point — mismo criterio que "Cobrar a mano" adentro
/// del diálogo de Point (`cobrarActual()` con el canal ya elegido), pero
/// elegible desde el arranque en vez de solo aparecer cuando la terminal
/// ya falló. El dueño, 2026-09-08: "necesito cobro manual... no hay más
/// modal para seleccionarlo" — con QR/Débito directo o el resto virtual
/// de un mixto, `canalElegido` ya está puesto apenas se elige el medio
/// (`elegirCanalDirecto`/`confirmarMixto`), así que no hace falta ningún
/// paso extra acá. Sin carrito o sin canal elegido no hay nada que hacer
/// — silencioso, no es un error pedir esto sin haber llegado hasta ahí.
Future<void> cobrarAMano(BuildContext context, VentaControlador c) async {
  if (c.carrito.isEmpty || c.canalElegido == null) return;
  await c.cobrarActual();
  c.focoCampoPrincipal.requestFocus();
}
