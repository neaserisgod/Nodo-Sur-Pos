// Barra inferior del mock (docs/01 §6.1): píldora flotante blanca de 68 px con
// cinco pestañas — Inicio · Productos · Vender (centro, azul, 52 px) · Caja ·
// Más — en una grilla `1fr 1fr 1.35fr 1fr 1fr`. La pestaña activa lleva una
// burbuja azul claro de 48×28; "Más" muestra un punto naranja si hay una
// actualización pendiente.
//
// Nodo Gastro (mock docs/mock-gastro/NodoGastro.html): cápsula flotante con cinco pestañas iguales, sin el botón azul en el medio;
// la activa lleva una cápsula de superficie detrás. Pedidos muestra cuántos esperan que alguien los acepte.

import 'package:flutter/material.dart';

import 'iconos_ns.dart';
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

enum PestaniaNs { inicio, productos, vender, caja, mas }

class BarraInferiorNs extends StatelessWidget {
  const BarraInferiorNs({super.key, required this.activa, required this.onSeleccionar, this.hayActualizacion = false, this.conServicios = false, this.conPedidos = false, this.pedidosNuevos = 0});

  /// Pedidos por aceptar (solo con [conPedidos]): el globo de la pestaña Pedidos.
  final int pedidosNuevos;

  final PestaniaNs activa;
  final ValueChanged<PestaniaNs> onSeleccionar;
  final bool hayActualizacion;

  /// Un negocio de servicios: la pestaña de Productos es Servicios (`pantalla_servicios_ns.dart`).
  final bool conServicios;

  /// Un local gastronómico (§22): Inicio es Pedidos y Productos es la Carta (los platos, con su receta).
  final bool conPedidos;

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
    if (conPedidos) return _barraGastro(context, ns, inferior);
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
                      ? _BotonVender(activo: activa == p, onTap: () => onSeleccionar(p), etiqueta: conServicios ? 'Cobrar' : 'Vender')
                      : _Pestania(
                          // En servicios la Agenda reemplaza al Inicio (`REGLAS-NEGOCIO.md` §21) y Productos pasa a Servicios.
                          etiqueta: conPedidos
                              ? switch (p) {
                                  PestaniaNs.inicio => 'Pedidos',
                                  PestaniaNs.productos => 'Carta',
                                  _ => etiqueta,
                                }
                              : !conServicios
                                  ? etiqueta
                                  : switch (p) {
                                      PestaniaNs.inicio => 'Agenda',
                                      PestaniaNs.productos => 'Servicios',
                                      _ => etiqueta,
                                    },
                          icono: p == PestaniaNs.inicio && conServicios
                              ? IconoNs.calendario
                              : p == PestaniaNs.inicio && conPedidos
                                  ? IconoNs.portapapeles
                                  : icono,
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

extension on BarraInferiorNs {
  Widget _barraGastro(BuildContext context, TokensNs ns, double inferior) {
    const etiquetas = {
      PestaniaNs.inicio: ('Pedidos', IconoNs.portapapeles),
      PestaniaNs.productos: ('Carta', IconoNs.producto),
      PestaniaNs.vender: ('Vender', IconoNs.carrito),
      PestaniaNs.caja: ('Caja', IconoNs.billetera),
      PestaniaNs.mas: ('Más', IconoNs.mas),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + inferior),
      child: Semantics(
        container: true,
        label: 'Secciones de la app',
        child: Container(
          height: 66,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            // En oscuro la cápsula se despega del fondo con una superficie, no con la sombra (que ahí no se ve).
            color: ns.oscuro ? ns.s2 : ns.paper,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0x0F1A1714), spreadRadius: 1),
              BoxShadow(color: Color(0x381A1714), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -14),
            ],
          ),
          child: Row(
            children: [
              for (final MapEntry(key: p, value: (etiqueta, icono)) in etiquetas.entries)
                Expanded(
                  child: _PestaniaGastro(
                    etiqueta: etiqueta,
                    icono: icono,
                    activa: activa == p,
                    globo: p == PestaniaNs.inicio ? pedidosNuevos : 0,
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

class _PestaniaGastro extends StatelessWidget {
  const _PestaniaGastro({required this.etiqueta, required this.icono, required this.activa, required this.globo, required this.punto, required this.onTap});

  final String etiqueta;
  final IconoNs icono;
  final bool activa;
  final int globo;
  final bool punto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final color = activa ? ns.ink : ns.mute;
    return Semantics(
      selected: activa,
      child: PresionNs(
        onTap: onTap,
        etiqueta: globo > 0 ? '$etiqueta, $globo nuevos' : etiqueta,
        child: AnimatedContainer(
          duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 250),
          decoration: BoxDecoration(color: activa ? (ns.oscuro ? ns.paper : ns.s) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconoNsWidget(icono, tamanio: 22, color: color, grosor: 2),
                  if (globo > 0)
                    Positioned(
                      top: -5,
                      right: -10,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: ns.acento, borderRadius: BorderRadius.circular(9)),
                        child: Text('$globo', style: estiloNs(11, peso: FontWeight.w700, color: ns.onAcento, tabular: true)),
                      ),
                    ),
                  if (punto)
                    Positioned(
                      top: -2,
                      right: -6,
                      child: Container(width: 9, height: 9, decoration: BoxDecoration(color: ns.acento, shape: BoxShape.circle)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(etiqueta, maxLines: 1, style: estiloNs(11, peso: FontWeight.w600, color: color)),
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
  const _BotonVender({required this.activo, required this.onTap, required this.etiqueta});

  final bool activo;
  final VoidCallback onTap;

  /// "Cobrar" en un negocio de servicios (mock de servicios): ahí no se vende, se cobra el turno.
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: activo,
      child: PresionNs(
        onTap: onTap,
        etiqueta: etiqueta,
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
                Text(etiqueta, style: estiloNs(13, peso: FontWeight.w700, color: TokensNs.blanco)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
