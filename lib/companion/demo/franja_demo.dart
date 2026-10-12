// La franja de arriba de la demo (horsepos.com/demo/): avisa que los datos son de ejemplo y lleva a probar gratis. Está siempre,
// en todas las pantallas, para que nadie confunda la demo con su negocio.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servicios/recargar_pagina.dart';
import '../kit/kit_ns.dart';
import 'demo.dart';

class FranjaDemo extends StatelessWidget {
  const FranjaDemo({super.key});

  static const double alto = 44;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Material(
      color: ns.ink,
      child: SizedBox(
        height: alto,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Lo primero que se achica en un celular angosto es este texto, nunca los botones.
              Expanded(
                child: Text(
                  'Es una demo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: estiloNs(13, peso: FontWeight.w700, color: ns.paper),
                ),
              ),
              // Recargar vuelve a "¿Qué negocio querés ver?": todo está en memoria.
              TextButton(
                key: const Key('demo-reiniciar'),
                onPressed: recargarPagina,
                style: TextButton.styleFrom(
                  foregroundColor: ns.paper,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  'Reiniciar',
                  style: estiloNs(13, peso: FontWeight.w600, color: ns.paper),
                ),
              ),
              const SizedBox(width: 4),
              // El azul de la marca: el acento del tema claro es casi negro y no se vería sobre la franja.
              FilledButton(
                key: const Key('demo-probar'),
                onPressed: () => launchUrl(Uri.base.resolve(rutaProbarGratis), webOnlyWindowName: '_blank'),
                style: FilledButton.styleFrom(
                  backgroundColor: TokensNs.marca,
                  foregroundColor: TokensNs.blanco,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Probar gratis',
                  style: estiloNs(13, peso: FontWeight.w700, color: TokensNs.blanco),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La app con la franja arriba, solo en la demo. Lo de abajo pierde el margen de arriba (la franja ya lo ocupa).
///
/// La franja aparece un cuadro después del primero: en el navegador, cuando la pestaña toma el foco, Flutter recorre los botones
/// para elegir el primero, y uno que todavía no se dibujó tiraba "RenderBox was not laid out" en la consola.
class ConFranjaDemo extends StatefulWidget {
  const ConFranjaDemo({super.key, required this.child});
  final Widget child;

  @override
  State<ConFranjaDemo> createState() => _ConFranjaDemoState();
}

class _ConFranjaDemoState extends State<ConFranjaDemo> {
  bool _botones = false;

  @override
  void initState() {
    super.initState();
    if (modoDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _botones = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!modoDemo) return widget.child;
    final arriba = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Container(
          color: context.ns.ink,
          padding: EdgeInsets.only(top: arriba),
          height: FranjaDemo.alto + arriba,
          child: _botones ? const FranjaDemo() : null,
        ),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
      ],
    );
  }
}
