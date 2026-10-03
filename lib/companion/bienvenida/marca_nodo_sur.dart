// El logo de Nodo Sur (el mismo de horsepos.com): cuadrado negro redondeado con "NS" y el punto verde. Se dibuja con
// widgets en vez de un asset porque la bienvenida lo arma por partes: el punto llega primero y el cuadrado crece desde él.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';

/// Verde del punto del logo (el de la web).
const verdeMarca = Color(0xFF34A853);

/// Dónde cae el centro del punto verde dentro del logo, como fracción del lado (el SVG de la web es de 40×40 y el
/// punto está en 32, 23,6).
const centroPuntoMarca = Offset(32 / 40, 23.6 / 40);

class MarcaNodoSur extends StatelessWidget {
  const MarcaNodoSur({super.key, this.tamanio = 40, this.opacidadTexto = 1, this.conPunto = true});

  final double tamanio;

  /// La bienvenida hace aparecer las letras después del cuadrado.
  final double opacidadTexto;

  /// Sin punto cuando lo dibuja aparte la animación (llega volando y se queda en su lugar).
  final bool conPunto;

  @override
  Widget build(BuildContext context) {
    final u = tamanio / 40;
    return SizedBox(
      width: tamanio,
      height: tamanio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12 * u)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 6.5 * u,
              top: 9.6 * u,
              child: Opacity(
                opacity: opacidadTexto.clamp(0.0, 1.0),
                child: Text(
                  'NS',
                  style: TextStyle(
                    fontFamily: familiaTipografica,
                    fontSize: 16.5 * u,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4 * u,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (conPunto)
              Positioned(
                left: (centroPuntoMarca.dx * 40 - 2.3) * u,
                top: (centroPuntoMarca.dy * 40 - 2.3) * u,
                child: Container(
                  width: 4.6 * u,
                  height: 4.6 * u,
                  decoration: const BoxDecoration(color: verdeMarca, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
