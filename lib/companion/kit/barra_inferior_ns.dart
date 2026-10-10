// Barra inferior del mock (docs/01 §6.1): píldora flotante blanca de 68 px con
// cinco pestañas — Inicio · Productos · Vender (centro, azul, 52 px) · Caja ·
// Más — en una grilla `1fr 1fr 1.35fr 1fr 1fr`. La pestaña activa lleva una
// burbuja azul claro de 48×28; "Más" muestra un punto naranja si hay una
// actualización pendiente.

import 'package:flutter/material.dart';

import 'iconos_ns.dart';
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

enum PestaniaNs { inicio, productos, vender, caja, mas }

class BarraInferiorNs extends StatelessWidget {
  const BarraInferiorNs({super.key, required this.activa, required this.onSeleccionar, this.hayActualizacion = false, this.servicios = false, this.agenda = false});

  final PestaniaNs activa;
  final ValueChanged<PestaniaNs> onSeleccionar;
  final bool hayActualizacion;

  /// Negocio de servicios (`docs/PLAN-SERVICIOS.md`): la pestaña Productos se llama Servicios.
  final bool servicios;

  /// Con la Agenda (Regla 21), la primera pestaña es la Agenda en lugar de Inicio.
  final bool agenda;

  /// Cuánto espacio inferior necesita el contenido para no quedar tapado:
  /// barra 68 + margen 16 + aire 40 (doc 01 §3).
  static const double espacioReservado = 124;
  static const double alto = 68;

  static const _datos = <(PestaniaNs, String, IconoNs)>[
    (PestaniaNs.inicio, 'Inicio', IconoNs.inicio),
    (PestaniaNs.productos, 'Productos', IconoNs.producto),
    (PestaniaNs.vender, 'Vender', IconoNs.carrito),
    (PestaniaNs.caja, 'Caja', IconoNs.billetera),
    (PestaniaNs.mas, 'Más', IconoNs.mas),
  ];

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final inferior = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + inferior),
      child: Semantics(
        container: true,
        label: 'Secciones de la app',
        child: Container(
          height: alto,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ns.paper,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0x0F121317), spreadRadius: 1),
              BoxShadow(color: Color(0x24121317), blurRadius: 28, offset: Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              for (final (p, etiqueta, icono) in _datos)
                Expanded(
                  flex: p == PestaniaNs.vender ? 135 : 100,
                  child: p == PestaniaNs.vender
                      ? _BotonVender(activo: activa == p, onTap: () => onSeleccionar(p))
                      : _Pestania(
                          etiqueta: p == PestaniaNs.productos && servicios ? 'Servicios' : (p == PestaniaNs.inicio && agenda ? 'Agenda' : etiqueta),
                          icono: p == PestaniaNs.inicio && agenda ? IconoNs.calendario : icono,
                          activa: activa == p,
                          punto: p == PestaniaNs.mas && hayActualizacion && activa != p,
                          onTap: () => onSeleccionar(p),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pestania extends StatelessWidget {
  const _Pestania({required this.etiqueta, required this.icono, required this.activa, required this.punto, required this.onTap});

  final String etiqueta;
  final IconoNs icono;
  final bool activa;
  final bool punto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final color = activa ? TokensNs.marca : ns.mute;
    return Semantics(
      selected: activa,
      child: PresionNs(
        onTap: onTap,
        etiqueta: etiqueta,
        child: Stack(
          children: [
            SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 200),
                    width: 48,
                    height: 28,
                    decoration: BoxDecoration(color: activa ? ns.ibg : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                    alignment: Alignment.center,
                    child: IconoNsWidget(icono, tamanio: 22, color: color, grosor: 2.1),
                  ),
                  const SizedBox(height: 2),
                  Text(etiqueta, maxLines: 1, style: estiloNs(13, peso: activa ? FontWeight.w700 : FontWeight.w600, color: color)),
                ],
              ),
            ),
            if (punto)
              Positioned(
                top: 8,
                right: 18,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: TokensNs.puntoActualizacion, shape: BoxShape.circle, boxShadow: [BoxShadow(color: ns.paper, spreadRadius: 2)]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BotonVender extends StatelessWidget {
  const _BotonVender({required this.activo, required this.onTap});

  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: activo,
      child: PresionNs(
        onTap: onTap,
        etiqueta: 'Vender',
        child: Center(
          child: Container(
            height: 52,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: activo ? TokensNs.marcaOscura : TokensNs.marca, borderRadius: BorderRadius.circular(999)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const IconoNsWidget(IconoNs.carrito, tamanio: 22, color: TokensNs.blanco, grosor: 2.1),
                const SizedBox(height: 1),
                Text('Vender', style: estiloNs(13, peso: FontWeight.w700, color: TokensNs.blanco)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
