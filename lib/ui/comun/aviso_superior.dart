// Aviso arriba (El dueño, rediseño v4, 2026-10-05: "me gustan las notificaciones, los avisos popup, pero quiero que salgan
// arriba"). Reemplaza a los `SnackBar`, que salían abajo y tapaban el cobro en Venta: una pastilla oscura centrada, justo
// debajo de la barra de la ventana, que baja con un fundido corto, se queda un rato y se va sola. Con `accion` (Deshacer)
// dura más para dar tiempo a tocarla.
//
// Un aviso nuevo reemplaza al anterior. Va en el `Overlay` raíz: se ve sobre cualquier pantalla o diálogo, y no depende
// de que haya un `Scaffold`. La permanencia es un `Timer` que se cancela al desmontarse: así la entrada es una animación
// corta (un `pumpAndSettle` de un test la deja a la vista, igual que el `SnackBar` de antes) y nada queda pendiente.

import 'dart:async';

import 'package:flutter/material.dart';

import '../kit/ic.dart';
import '../kit/mov.dart';
import '../kit/paleta.dart';
import '../kit/texto.dart';
import '../kit/tocable.dart';

/// Cuánto se queda un aviso simple, y uno con acción.
const Duration duracionAvisoSimple = Duration(milliseconds: 2600);
const Duration duracionAvisoConAccion = Duration(seconds: 5);

const Duration _entrada = Duration(milliseconds: 450);
const Duration _salida = Duration(milliseconds: 300);

/// Distancia del borde de arriba del contenido (la barra de la ventana ya está arriba del `Navigator`): deja el aviso
/// sobre la franja de la navbar, como en el mock.
const double _separacionSuperior = 18;

OverlayEntry? _entradaActual;

/// Muestra [texto] arriba. Con [textoAccion] y [alAccionar], suma un botón (ej. "Deshacer"). Devuelve sin esperar.
///
/// Si no hay `Overlay` (una pantalla suelta en un test sin `Navigator`), cae a un `SnackBar` para no perder el aviso.
void mostrarAviso(
  BuildContext context,
  String texto, {
  String? textoAccion,
  VoidCallback? alAccionar,
  Duration? duracion,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(texto),
        action: textoAccion == null ? null : SnackBarAction(label: textoAccion, onPressed: alAccionar ?? () {}),
      ),
    );
    return;
  }
  _quitarActual();
  final conAccion = textoAccion != null;
  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (_) => _AvisoSuperior(
      texto: texto,
      textoAccion: textoAccion,
      alAccionar: alAccionar,
      permanencia: duracion ?? (conAccion ? duracionAvisoConAccion : duracionAvisoSimple),
      alTerminar: () {
        if (_entradaActual == entrada) _entradaActual = null;
        if (entrada.mounted) entrada.remove();
      },
    ),
  );
  _entradaActual = entrada;
  overlay.insert(entrada);
}

/// Saca el aviso que esté a la vista (por ejemplo al cambiar de pantalla).
void ocultarAviso() => _quitarActual();

void _quitarActual() {
  final actual = _entradaActual;
  _entradaActual = null;
  if (actual != null && actual.mounted) actual.remove();
}

class _AvisoSuperior extends StatefulWidget {
  const _AvisoSuperior({
    required this.texto,
    required this.permanencia,
    required this.alTerminar,
    this.textoAccion,
    this.alAccionar,
  });

  final String texto;
  final String? textoAccion;
  final VoidCallback? alAccionar;
  final Duration permanencia;
  final VoidCallback alTerminar;

  @override
  State<_AvisoSuperior> createState() => _AvisoSuperiorState();
}

class _AvisoSuperiorState extends State<_AvisoSuperior> with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;
  late final Animation<double> _aparicion;
  Timer? _permanencia;

  @override
  void initState() {
    super.initState();
    _controlador = AnimationController(vsync: this, duration: _entrada, reverseDuration: _salida);
    _aparicion = CurvedAnimation(parent: _controlador, curve: curvaBack, reverseCurve: Curves.easeIn);
    _controlador.addStatusListener((estado) {
      if (estado == AnimationStatus.dismissed) widget.alTerminar();
    });
    _controlador.forward();
    _permanencia = Timer(widget.permanencia + _entrada, () {
      if (mounted) _controlador.reverse();
    });
  }

  @override
  void dispose() {
    _permanencia?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  /// Tocar la acción la usa y saca el aviso al toque.
  void _accionar() {
    widget.alAccionar?.call();
    widget.alTerminar();
  }

  @override
  Widget build(BuildContext context) {
    // `.toast` del mock v4: pastilla de 60 px que baja con rebote (`--back`, 450 ms), tilde + texto 17/600 y "Deshacer".
    final p = context.p;
    return Positioned(
      top: _separacionSuperior,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _controlador,
          builder: (context, hijo) {
            final v = _aparicion.value;
            return Opacity(
              opacity: _controlador.value.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, -26 * (1 - v)), child: hijo),
            );
          },
          child: Semantics(
            liveRegion: true,
            container: true,
            label: widget.texto,
            child: Container(
              key: const Key('aviso_superior'),
              constraints: const BoxConstraints(minHeight: 60, maxWidth: 820),
              padding: EdgeInsets.only(left: 22, right: widget.textoAccion == null ? 30 : 12),
              decoration: BoxDecoration(
                color: p.toast,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 50, offset: Offset(0, 20))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icono(Ic.check, size: 20, color: p.sobreToast, grosor: 2.6),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(widget.texto, style: estilo(17, 600, color: p.sobreToast), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  if (widget.textoAccion != null) ...[
                    const SizedBox(width: 22),
                    Tocable(
                      key: const Key('aviso_superior_accion'),
                      onTap: _accionar,
                      radio: 18,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icono(Ic.undo, size: 16, color: p.sobreToast, grosor: 2.4),
                            const SizedBox(width: 6),
                            Text(widget.textoAccion!, style: estilo(14, 600, color: p.sobreToast)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
