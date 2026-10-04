// Movimiento del mock (docs/01 §5): una sola curva, `cubic-bezier(.2,.7,.1,1)`,
// entradas que suben 14 px con fade y todo se apaga con "reducir movimiento".

import 'package:flutter/material.dart';

const Curve curvaNs = Cubic(.2, .7, .1, 1);

/// `true` si el sistema pidió reducir el movimiento.
bool sinMovimiento(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Entrada de pantalla (`.scr`, 0,55 s) o de tarjeta/fila (`.rv`, 0,6 s):
/// aparece con fade y sube desde 14 px. Se dispara solo cuando el widget se
/// monta, no en cada actualización de datos.
class EntradaNs extends StatefulWidget {
  const EntradaNs({super.key, required this.child, this.duracion = const Duration(milliseconds: 600), this.retraso = Duration.zero});

  final Widget child;
  final Duration duracion;
  final Duration retraso;

  @override
  State<EntradaNs> createState() => _EntradaNsState();
}

class _EntradaNsState extends State<EntradaNs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duracion);
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (sinMovimiento(context)) {
      _c.value = 1;
    } else if (widget.retraso == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.retraso, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: curvaNs);
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 14 * (1 - t.value)), child: child),
      ),
    );
  }
}

/// Pantalla completa: misma entrada con 0,55 s.
class PantallaEntradaNs extends StatelessWidget {
  const PantallaEntradaNs({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => EntradaNs(duracion: const Duration(milliseconds: 550), child: child);
}

/// Feedback de toque del mock (`.press`): al apretar baja a 0,97 con la curva
/// universal (0,3 s).
class PresionNs extends StatefulWidget {
  const PresionNs({super.key, required this.child, required this.onTap, this.etiqueta, this.habilitado = true, this.comportamiento = HitTestBehavior.opaque});

  final Widget child;
  final VoidCallback? onTap;
  final String? etiqueta;
  final bool habilitado;
  final HitTestBehavior comportamiento;

  @override
  State<PresionNs> createState() => _PresionNsState();
}

class _PresionNsState extends State<PresionNs> {
  bool _abajo = false;

  void _fijar(bool v) {
    if (_abajo != v && mounted) setState(() => _abajo = v);
  }

  @override
  Widget build(BuildContext context) {
    final activo = widget.habilitado && widget.onTap != null;
    final reducido = sinMovimiento(context);
    return Semantics(
      button: true,
      enabled: activo,
      label: widget.etiqueta,
      child: GestureDetector(
        behavior: widget.comportamiento,
        onTapDown: activo ? (_) => _fijar(true) : null,
        onTapUp: activo ? (_) => _fijar(false) : null,
        onTapCancel: activo ? () => _fijar(false) : null,
        onTap: activo ? widget.onTap : null,
        child: AnimatedScale(
          scale: _abajo && !reducido ? 0.97 : 1,
          duration: reducido ? Duration.zero : const Duration(milliseconds: 300),
          curve: curvaNs,
          child: widget.etiqueta == null ? widget.child : ExcludeSemantics(child: widget.child),
        ),
      ),
    );
  }
}
