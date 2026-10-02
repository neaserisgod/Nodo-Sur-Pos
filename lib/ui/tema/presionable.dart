// Feedback de presión para cualquier fila o tarjeta tocable — puerto de
// `lib/companion/tema/presionable.dart`. El `InkWell` de acá ya hereda
// `hoverColor` del tema global (`TemaPlazoleta`, `tema.dart`) sin código
// extra — señal real de mouse que la companion no tiene, al no haber
// puntero. Reemplaza el `Material`+`InkWell` armado a mano en
// `FilaLista`/`BarraLateral`/etc. — mismo espíritu que `TactoVenta` de
// Venta (`lib/ui/venta/tacto_venta.dart`), sin compartir código con esa
// pantalla (se reconcilian recién en la Fase 5 del remake, no antes).

import 'package:flutter/material.dart';

import 'tema_inverso.dart';
import 'tokens.dart';

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
      // "Dark glass premium" (El dueño, rediseño 2026-09-25): overshoot leve al
      // soltar (`curvaSpring`) da la sensación de rebote físico — con un
      // delta tan chico (3%) el overshoot en la ida a 0.97 no se percibe
      // gomoso, así que alcanza una sola curva para las dos direcciones.
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
          child: TemaInverso(
            activo: widget.color != null && widget.color == context.colores.acento,
            child: widget.child,
          ),
        ),
      ),
    );
    final nombre = widget.etiqueta;
    if (nombre == null) return boton;
    return Semantics(button: true, enabled: widget.onTap != null, label: nombre, excludeSemantics: true, onTap: widget.onTap, child: boton);
  }
}
