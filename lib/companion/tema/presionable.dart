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
    this.etiqueta,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Para entrar a un modo de selección múltiple manteniendo presionada una
  /// fila (El dueño, 2026-09-19: "editor masivo") — opcional, `null` es el
  /// comportamiento de siempre (solo toque corto).
  final VoidCallback? onLongPress;
  final double radio;

  /// Nombre para el lector de pantalla. Hace falta cuando el hijo es solo un
  /// ícono o un dibujo (una campanita, un tilde): sin esto no se anuncia nada.
  final String? etiqueta;

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
    final boton = AnimatedScale(
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
    final nombre = widget.etiqueta;
    if (nombre == null) return boton;
    return Semantics(button: true, enabled: widget.onTap != null, label: nombre, excludeSemantics: true, onTap: widget.onTap, child: boton);
  }
}
