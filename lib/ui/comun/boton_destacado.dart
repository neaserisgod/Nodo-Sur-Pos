// CTA con degradé — análogo de escritorio del patrón `_CtaVender` de la
// companion (botón hero de una sola acción principal por pantalla, ej.
// "Ir a vender" del Dashboard sin caja abierta). Pieza nueva, opt-in: no
// reemplaza a `BotonPrimario` en todos lados, es para el único llamado a
// la acción de una pantalla que lo necesite (remake de la estética, el dueño
// 2026-09-19).

import 'package:flutter/material.dart';

import '../tema/acentos.dart';
import '../tema/presionable.dart';
import '../tema/resplandor.dart';
import '../tema/tokens.dart';

class BotonDestacado extends StatelessWidget {
  const BotonDestacado({
    super.key,
    required this.texto,
    required this.onTap,
    this.icono,
    this.degrade,
  });

  final String texto;
  final VoidCallback? onTap;
  final IconData? icono;

  /// Por defecto el degradé de acento (`acentosPlazoleta.gradienteAcento`)
  /// — puede pisarse (ej. `gradienteDinero`, para el CTA de cobrar).
  final List<Color>? degrade;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final gradiente = degrade ?? acentos.gradienteAcento;
    // Pastilla, como todos los botones del lenguaje nuevo (2026-09-26).
    return Presionable(
      radio: Medidas.alturaControl / 2,
      onTap: onTap,
      child: Container(
        height: Medidas.alturaControl,
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradiente, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(Medidas.alturaControl / 2),
          boxShadow: resplandorNeon(gradiente.first, alpha: 0.35, radio: 16),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, color: acentos.textoSobreColor, size: 20),
              const SizedBox(width: Espaciado.sm),
            ],
            Text(
              texto,
              style: TextStyle(color: acentos.textoSobreColor, fontWeight: Pesos.medium),
            ),
          ],
        ),
      ),
    );
  }
}
