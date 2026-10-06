// Base de todo lo que se toca en el kit: click, Enter/Espacio con el foco, cursor de mano y el aro de foco del mock
// (`:focus-visible{outline:3px solid var(--focus);outline-offset:2px}`) que solo aparece al llegar con el teclado.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'paleta.dart';

class Tocable extends StatefulWidget {
  const Tocable({
    super.key,
    required this.onTap,
    required this.radio,
    required this.child,
    this.etiqueta,
    this.tooltip,
    this.seleccionado,
    this.focusNode,
    this.autofocus = false,
    this.onDoubleTap,
    this.puedeEnfocarse = true,
  });

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Radio del aro de foco (el mismo del dibujo).
  final double radio;
  final Widget child;

  /// Nombre para lectores de pantalla cuando el contenido es solo un ícono.
  final String? etiqueta;
  final String? tooltip;

  /// Para `aria-pressed`: chips, pestañas, medios de pago.
  final bool? seleccionado;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool puedeEnfocarse;

  @override
  State<Tocable> createState() => _TocableState();
}

class _TocableState extends State<Tocable> {
  bool _focoTeclado = false;

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.onTap != null;
    Widget w = FocusableActionDetector(
      enabled: habilitado,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      descendantsAreFocusable: false,
      mouseCursor: habilitado ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focoTeclado = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: CustomPaint(
          foregroundPainter: _focoTeclado ? _AroFoco(widget.radio) : null,
          child: widget.child,
        ),
      ),
    );
    w = Semantics(
      button: true,
      enabled: habilitado,
      selected: widget.seleccionado,
      label: widget.etiqueta,
      child: w,
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 500), child: w);
    if (!widget.puedeEnfocarse) w = ExcludeFocus(child: w);
    return _MinimoToque(child: w);
  }
}

class _AroFoco extends CustomPainter {
  _AroFoco(this.radio);
  final double radio;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius((Offset.zero & size).inflate(3.5), Radius.circular(radio + 3.5));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = PaletaMock.foco,
    );
  }

  @override
  bool shouldRepaint(_AroFoco old) => old.radio != radio;
}

/// Área mínima de 48 para algo que no es un botón del kit (un campo de texto dibujado más bajo, por ejemplo): lo que se
/// anuncia y lo que recibe el click mide al menos 48, sin cambiar el dibujo.
class AreaMinimaToque extends StatelessWidget {
  const AreaMinimaToque({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => _MinimoToque(child: child);
}

/// El mock dibuja botones de 34–46 px (el stepper, el tacho, los chips chicos), pero con el mouse y con el dedo se
/// tienen que poder apretar como uno de 48 (la guía de accesibilidad que miden los tests). Esto agranda el área que
/// recibe el click y la que se anuncia, centrada, SIN cambiar el dibujo ni el lugar que ocupa.
class _MinimoToque extends SingleChildRenderObjectWidget {
  const _MinimoToque({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMinimoToque();
}

class _RenderMinimoToque extends RenderProxyBox {
  static const _minimo = 48.0;

  Rect get _area {
    final dx = size.width < _minimo ? (_minimo - size.width) / 2 : 0.0;
    final dy = size.height < _minimo ? (_minimo - size.height) / 2 : 0.0;
    return Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
  }

  @override
  Rect get semanticBounds => _area;

  // Un nodo propio que junta lo de adentro (el botón, su texto): así lo que se anuncia mide el área agrandada.
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.isMergingSemanticsOfDescendants = true;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_area.contains(position)) return false;
    final dentro = Offset(position.dx.clamp(0, size.width), position.dy.clamp(0, size.height));
    if (hitTestChildren(result, position: dentro) || hitTestSelf(dentro)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
