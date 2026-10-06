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

import '../tema/iconos.dart';
import '../tema/tokens.dart';

/// Cuánto se queda un aviso simple, y uno con acción.
const Duration duracionAvisoSimple = Duration(milliseconds: 2600);
const Duration duracionAvisoConAccion = Duration(seconds: 5);

const Duration _entrada = Duration(milliseconds: 220);
const Duration _salida = Duration(milliseconds: 200);

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
    _aparicion = CurvedAnimation(parent: _controlador, curve: Animaciones.curva, reverseCurve: Curves.easeIn);
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
    final tema = Theme.of(context);
    final fondo = tema.snackBarTheme.backgroundColor ?? const Color(0xFF121317);
    final estiloTexto = (tema.textTheme.bodyLarge ?? const TextStyle()).copyWith(color: Colors.white, fontWeight: Pesos.medium);
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
              opacity: v.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, -26 * (1 - v)), child: hijo),
            );
          },
          child: Semantics(
            liveRegion: true,
            container: true,
            label: widget.texto,
            child: Material(
              key: const Key('aviso_superior'),
              color: fondo,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              shape: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56, maxWidth: 720),
                child: Padding(
                  padding: EdgeInsets.only(left: Espaciado.lg, right: widget.textoAccion == null ? Espaciado.xl : Espaciado.sm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IconoPlz(IconosPlazoleta.check, size: 20, color: Colors.white),
                      const SizedBox(width: Espaciado.md),
                      Flexible(child: Text(widget.texto, style: estiloTexto, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      if (widget.textoAccion != null) ...[
                        const SizedBox(width: Espaciado.md),
                        TextButton(
                          key: const Key('aviso_superior_accion'),
                          onPressed: _accionar,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(alpha: 0.16),
                            padding: const EdgeInsets.symmetric(horizontal: Espaciado.md),
                            minimumSize: const Size(0, 36),
                            shape: const StadiumBorder(),
                            textStyle: (tema.textTheme.bodyMedium ?? const TextStyle()).copyWith(fontWeight: Pesos.fuerte),
                          ),
                          child: Text(widget.textoAccion!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
