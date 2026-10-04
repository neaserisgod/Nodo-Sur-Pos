// El visor de la pantalla Emparejar (docs/03 A1): tarjeta oscura con el marco de
// escaneo de 200×200 (cuatro esquinas de 46 con borde blanco de 4), la línea azul
// que sube y baja (3,2 s) y el texto de pie. Acá acompaña la búsqueda de la PC.

import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';

class VisorNs extends StatefulWidget {
  const VisorNs({super.key, required this.pie});
  final String pie;

  @override
  State<VisorNs> createState() => _VisorNsState();
}

class _VisorNsState extends State<VisorNs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    // Con "reducir movimiento" la línea queda quieta en el medio.
    if (sinMovimiento(context)) {
      _c.value = 0.5;
    } else {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _esquina({required bool izq, required bool arriba}) {
    const borde = BorderSide(color: TokensNs.blanco, width: 4);
    const r = Radius.circular(18);
    return Positioned(
      left: izq ? 0 : null,
      right: izq ? null : 0,
      top: arriba ? 0 : null,
      bottom: arriba ? null : 0,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          border: Border(left: izq ? borde : BorderSide.none, right: izq ? BorderSide.none : borde, top: arriba ? borde : BorderSide.none, bottom: arriba ? BorderSide.none : borde),
          borderRadius: BorderRadius.only(topLeft: izq && arriba ? r : Radius.zero, topRight: !izq && arriba ? r : Radius.zero, bottomLeft: izq && !arriba ? r : Radius.zero, bottomRight: !izq && !arriba ? r : Radius.zero),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HeroNs(
      radio: 40,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                children: [
                  _esquina(izq: true, arriba: true),
                  _esquina(izq: false, arriba: true),
                  _esquina(izq: true, arriba: false),
                  _esquina(izq: false, arriba: false),
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Positioned(
                      left: 14,
                      right: 14,
                      top: 200 * (0.14 + 0.68 * Curves.easeInOut.transform(_c.value)),
                      child: Container(height: 3, decoration: BoxDecoration(color: TokensNs.foco, borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 22, child: Text(widget.pie, textAlign: TextAlign.center, style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xCCFFFFFF)))),
        ],
      ),
    );
  }
}
