// Entrada escalonada de las pantallas del primer arranque (elegir modo, entrar con la cuenta, listo): cada pieza sube
// 16 px y aparece, una detrás de la otra, con la misma curva que la bienvenida. Así las pantallas que siguen a la
// bienvenida hablan el mismo idioma que ella, en vez de aparecer de golpe.

import 'package:flutter/material.dart';

/// Curva desacelerada de Material 3: arranca rápido y se posa suave.
const curvaEntrada = Cubic(0.05, 0.7, 0.1, 1);

class Aparecer extends StatefulWidget {
  const Aparecer({super.key, required this.orden, required this.child});

  /// Posición en la secuencia: cada paso demora 80 ms más que el anterior.
  final int orden;
  final Widget child;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer> with SingleTickerProviderStateMixin {
  static const _paso = 80;
  static const _duracion = 650;

  late final AnimationController _reloj = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.orden * _paso + _duracion),
  );
  late final Animation<double> _k = CurvedAnimation(
    parent: _reloj,
    curve: Interval(widget.orden * _paso / (widget.orden * _paso + _duracion), 1, curve: curvaEntrada),
  );
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    // Con "reducir animaciones" (y en los tests) la pantalla aparece entera, sin esperar a nada.
    if (MediaQuery.disableAnimationsOf(context)) {
      _reloj.value = 1;
    } else {
      _reloj.forward();
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _k,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _k.value,
        child: Transform.translate(offset: Offset(0, (1 - _k.value) * 16), child: child),
      ),
    );
  }
}
