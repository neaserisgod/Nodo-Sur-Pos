// Feedback de presión ("¿el toque entró?") para cualquier fila o tarjeta
// tocable de la companion — antes cada pantalla repetía
// `Material(type: transparency, child: InkWell(...))` con solo el ripple de
// Material como señal. Acá se suma un achique leve al presionar
// (`AnimatedScale`), mismo espíritu que `TactoVenta`/`SuperficieTactil` del
// escritorio (`lib/ui/venta/tacto_venta.dart`) pero con su propia curva y
// radio — "esto es un botón que se hunde", sin compartir código con esa
// pantalla (no tiene sentido que la venta de escritorio dependa de la
// companion ni viceversa).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';

class Presionable extends StatefulWidget {
  const Presionable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radio = 22,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Para entrar a un modo de selección múltiple manteniendo presionada una
  /// fila (El dueño, 2026-09-19: "editor masivo") — opcional, `null` es el
  /// comportamiento de siempre (solo toque corto).
  final VoidCallback? onLongPress;
  final double radio;

  /// Color de fondo del `Material` que envuelve — por defecto transparente
  /// (la superficie que lo contiene ya tiene su color).
  final Color? color;

  @override
  State<Presionable> createState() => _PresionableState();
}

class _PresionableState extends State<Presionable> {
  bool _presionado = false;

  void _fijar(bool valor) {
    if (widget.onTap == null) return;
    setState(() => _presionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      // "Dark glass premium" (El dueño, rediseño 2026-09-25) — mismo criterio
      // que `lib/ui/tema/presionable.dart`: overshoot leve al soltar.
      scale: _presionado ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Animaciones.curvaSpring,
      child: Material(
        color: widget.color ?? Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radio),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _fijar(true),
          onTapCancel: () => _fijar(false),
          onTapUp: (_) => _fijar(false),
          borderRadius: BorderRadius.circular(widget.radio),
          child: widget.child,
        ),
      ),
    );
  }
}
