// Avisos del mock: el aviso flotante (toast) y el cartel de "sin conexión".

import 'dart:async';

import 'package:flutter/material.dart';

import 'iconos_ns.dart';
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

OverlayEntry? _avisoActual;
Timer? _temporizador;

/// Aviso flotante (docs/01 §6.14): `left/right 24`, `bottom 100`, padding
/// 16/22, radio 26, fondo `toast`, texto blanco 15/600 centrado. Se va solo a
/// los 2,6 s (3,4 s si es largo).
void mostrarAvisoNs(BuildContext context, String texto, {bool largo = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  mostrarAvisoEnNs(overlay, texto, largo: largo);
}

/// Igual que [mostrarAvisoNs] pero con el overlay ya en mano: sirve cuando el
/// aviso sale justo después de cerrar una hoja (su contexto ya no existe).
void mostrarAvisoEnNs(OverlayState overlay, String texto, {bool largo = false}) {
  _temporizador?.cancel();
  _avisoActual?.remove();
  final entrada = OverlayEntry(builder: (_) => _AvisoNs(texto: texto));
  _avisoActual = entrada;
  overlay.insert(entrada);
  _temporizador = Timer(Duration(milliseconds: largo ? 3400 : 2600), () {
    if (_avisoActual == entrada) {
      entrada.remove();
      _avisoActual = null;
    }
  });
}

/// Aviso con una acción (mock `hasUndo`): píldora oscura de 68 de alto sobre la barra inferior, con "Quitaste X" y un botón blanco
/// "Deshacer". Dura 5 s; si llega otro aviso o se toca la acción, se va.
void mostrarAvisoConAccionNs(BuildContext context, String texto, String accion, VoidCallback alTocar) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _temporizador?.cancel();
  _avisoActual?.remove();
  late final OverlayEntry entrada;
  void quitar() {
    if (_avisoActual == entrada) {
      _temporizador?.cancel();
      entrada.remove();
      _avisoActual = null;
    }
  }

  entrada = OverlayEntry(
    builder: (_) => _AvisoAccionNs(
      texto: texto,
      accion: accion,
      alTocar: () {
        quitar();
        alTocar();
      },
    ),
  );
  _avisoActual = entrada;
  overlay.insert(entrada);
  _temporizador = Timer(const Duration(seconds: 5), quitar);
}

class _AvisoAccionNs extends StatelessWidget {
  const _AvisoAccionNs({required this.texto, required this.accion, required this.alTocar});
  final String texto;
  final String accion;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: EntradaNs(
        duracion: const Duration(milliseconds: 450),
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 68,
            padding: const EdgeInsets.fromLTRB(26, 0, 10, 0),
            decoration: BoxDecoration(
              color: ns.toast,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [BoxShadow(color: Color(0x47121317), blurRadius: 40, offset: Offset(0, 18))],
            ),
            child: Row(
              children: [
                Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w600, color: TokensNs.blanco))),
                const SizedBox(width: 10),
                PresionNs(
                  onTap: alTocar,
                  etiqueta: accion,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: BoxDecoration(color: TokensNs.blanco, borderRadius: BorderRadius.circular(999)),
                    child: Center(widthFactor: 1, child: Text(accion, style: estiloNs(15, peso: FontWeight.w600, color: const Color(0xFF121317)))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisoNs extends StatefulWidget {
  const _AvisoNs({required this.texto});
  final String texto;

  @override
  State<_AvisoNs> createState() => _AvisoNsState();
}

class _AvisoNsState extends State<_AvisoNs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _listo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listo) return;
    _listo = true;
    if (sinMovimiento(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final t = CurvedAnimation(parent: _c, curve: curvaNs);
    return Positioned(
      left: 24,
      right: 24,
      bottom: 100,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: t,
          builder: (context, child) => Opacity(
            opacity: t.value.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, 14 * (1 - t.value)), child: Transform.scale(scale: 0.96 + 0.04 * t.value, child: child)),
          ),
          child: Semantics(
            liveRegion: true,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  color: ns.toast,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [BoxShadow(color: Color(0x4D121317), blurRadius: 40, offset: Offset(0, 18))],
                ),
                child: Text(widget.texto, textAlign: TextAlign.center, style: estiloNs(15, peso: FontWeight.w600, altura: 1.35, color: TokensNs.blanco)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartel global "Sin conexión con la PC" (docs/01 §6.15): tira de 34 px de
/// ancho completo, fondo `wbg`, texto `w` 13/700 con puntito ámbar.
class CartelSinConexionNs extends StatelessWidget {
  const CartelSinConexionNs({super.key});

  static const double alto = 34;
  static const String texto = 'Sin conexión con la PC · usás los datos del celular';

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return EntradaNs(
      child: Container(
        height: alto,
        width: double.infinity,
        color: ns.wbg,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: TokensNs.puntoSinConexion, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(texto, style: estiloNs(13, peso: FontWeight.w700, color: ns.w)),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío (docs/01 §6.16): círculo de 72 con tilde y texto 20/500.
class EstadoVacioNs extends StatelessWidget {
  const EstadoVacioNs({super.key, required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: ns.gbg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: IconoNsWidget(IconoNs.tilde, tamanio: 32, color: ns.g, grosor: 2.6),
        ),
        const SizedBox(height: 14),
        Text(texto, textAlign: TextAlign.center, style: estiloNs(20, peso: FontWeight.w500, color: ns.ink)),
      ],
    );
  }
}
