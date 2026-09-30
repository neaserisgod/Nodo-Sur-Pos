// Skeleton de carga — puerto de
// `lib/companion/tema/esqueleto_companion.dart`. El escritorio hoy solo
// tiene spinners de pantalla completa en su carga inicial; esto reemplaza
// ese `Center(child: CircularProgressIndicator())` por la silueta de lo que
// está por aparecer, mismo criterio ya aplicado en la companion (El dueño,
// 2026-09-19: "si algo tarda en cargar no quiero pantallas en blanco o
// spinners, sino skeletons").
//
// Primitiva única (`EsqueletoCaja`, con su propia animación de pulso) más
// dos formas listas para usar: `EsqueletoLinea` (una barra) y
// `EsqueletoLista` (unas pocas filas con la silueta genérica de una fila de
// lista).

import 'package:flutter/material.dart';

import 'superficie.dart';
import 'tokens.dart';

class EsqueletoCaja extends StatefulWidget {
  const EsqueletoCaja({super.key, this.width, required this.height, this.radio = 8});

  final double? width;
  final double height;
  final double radio;

  @override
  State<EsqueletoCaja> createState() => _EsqueletoCajaState();
}

class _EsqueletoCajaState extends State<EsqueletoCaja> with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;

  @override
  void initState() {
    super.initState();
    _controlador = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colores.borde;
    return AnimatedBuilder(
      animation: _controlador,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: 0.35 + _controlador.value * 0.35),
            borderRadius: BorderRadius.circular(widget.radio),
          ),
        );
      },
    );
  }
}

/// Una sola barra — para un dato de una línea (un título, un monto) fuera
/// de una lista completa.
class EsqueletoLinea extends StatelessWidget {
  const EsqueletoLinea({super.key, this.width, this.height = 14});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      EsqueletoCaja(width: width, height: height, radio: height / 2);
}

/// Unas pocas filas con la silueta genérica de una fila de lista —
/// reemplaza al spinner centrado en cualquier pantalla que muestre una
/// lista mientras carga por primera vez.
class EsqueletoLista extends StatelessWidget {
  const EsqueletoLista({super.key, this.filas = 6});

  final int filas;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(Espaciado.lg),
      itemCount: filas,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: Espaciado.sm),
        child: Superficie(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    EsqueletoLinea(width: 160),
                    SizedBox(height: Espaciado.sm),
                    EsqueletoLinea(width: 90, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: Espaciado.lg),
              const EsqueletoLinea(width: 56, height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
