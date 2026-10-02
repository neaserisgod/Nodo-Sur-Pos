// Excepción puntual de venta (El dueño, 2026-09-16: "que la interfaz sea
// llamativa, al estilo de que parezca táctil, al menos en la pantalla de
// venta"). Mismo criterio que ya usa DISENO.md para la escala tipográfica de
// venta ("Excepción puntual, solo en venta"): un préstamo LOCAL a los
// widgets propios de esta pantalla, nunca una redefinición de los tokens
// compartidos.
//
// Reanclado en el remake de estética (2026-09-19): el radio sigue siendo
// una excepción local, ahora entre los dos radios nuevos
// (`radioControlEscritorio`=18, `radioSuperficieEscritorio`=22) en vez de
// entre los viejos (`Radios.control`=8, `Bento.radio`=14) — mismo criterio
// de siempre, un botón grande se lee como control táctil sin confundirse
// con un bloque de contenido. `SuperficieTactil` sigue siendo el mecanismo
// propio de Venta en vez de compartir `Presionable`
// (`lib/ui/tema/presionable.dart`): tiene su propio ajuste fino (escala
// 0.96 en vez de 0.97, la curva/duración de `Animaciones` en vez de las
// hardcodeadas de `Presionable`) ya probado en esta pantalla — no hay
// necesidad real de unificar solo por unificar.
//
// Sigue operándose con mouse/teclado (el campo único con foco permanente,
// CLAUDE.md); esto es solo la SENSACIÓN de una superficie táctil: objetivos
// más grandes, más redondeados, y un feedback de "esto se hundió" al
// presionar. Sin agregar color nuevo ni sombra — el principio de "evitar
// fatiga visual" (DISENO.md) sigue gobernando, la parte "llamativa" sale de
// forma y movimiento, no de contraste.

import 'package:flutter/material.dart';

import '../tema/tema_inverso.dart';

import '../tema/tokens.dart';

abstract final class TactoVenta {
  /// Entre `radioControlEscritorio` (18) y `radioSuperficieEscritorio` (22)
  /// — un botón grande se lee como control táctil, nunca se confunde con
  /// una `Superficie` de contenido.
  static const double radio = 28;

  /// Altura de los botones grandes de venta (medios de pago, "Cobrar",
  /// "$"/"%" del descuento). Sigue siendo `Medidas.alturaControl` (48), a
  /// propósito: la columna de cobro ya está ajustada al límite en el piso
  /// mínimo (1366×768, `DISENO.md`: "esta columna ya no tiene margen
  /// vertical de sobra para un bloque más") — siete controles con esta
  /// altura (dos del descuento, cuatro medios de pago, "Cobrar") no dejan
  /// margen para agrandarla sin forzar scroll, que CLAUDE.md prohíbe acá. La
  /// sensación táctil sale del radio, el ícono más grande y el feedback de
  /// presión, no de más alto.
  static const double alturaControl = Medidas.alturaControl;

  /// Tamaño de ícono para las acciones sueltas del carrito y la búsqueda
  /// (+/−, tacho) — más grande que el ícono chico de escritorio (18-20) que
  /// usa el resto de la app.
  static const double icono = 24;
}

/// Envoltorio táctil reutilizable para una superficie que arma su propio
/// `onTap` (fila de resultado, ícono de acción, botón de medio de pago):
/// ripple de Material (ya está en toda la app desde fase 13) + un achique
/// breve al presionar (`Animaciones.corta`, ya existe) que vuelve al
/// soltar — la sensación de "botón que se hunde". Responde siempre a una
/// acción del usuario, nunca se mueve solo (regla de "fatiga visual",
/// DISENO.md), así que no es una animación decorativa.
class SuperficieTactil extends StatefulWidget {
  const SuperficieTactil({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color = Colors.transparent,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final BorderRadius? borderRadius;

  @override
  State<SuperficieTactil> createState() => _SuperficieTactilState();
}

class _SuperficieTactilState extends State<SuperficieTactil> {
  bool _presionado = false;

  void _fijar(bool valor) {
    if (_presionado == valor) return;
    setState(() => _presionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _presionado ? 0.96 : 1.0,
      duration: Animaciones.corta,
      curve: Animaciones.curva,
      child: Material(
        color: widget.color,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: widget.onTap == null ? null : (_) => _fijar(true),
          onTapCancel: () => _fijar(false),
          onTapUp: (_) => _fijar(false),
          child: TemaInverso(
            activo: widget.color == context.colores.acento,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
