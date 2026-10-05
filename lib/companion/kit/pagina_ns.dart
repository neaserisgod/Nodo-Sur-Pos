// Páginas de arranque del mock (bienvenida, modo de uso, emparejar, entrar con la cuenta, asistente): fondo `paper`,
// padding 28/20/20, arriba la marca "NS · Nodo Sur" (o el botón de volver con el título), el título grande, la bajada,
// el cuerpo que scrollea y los botones fijos abajo.

import 'package:flutter/material.dart';

import 'movimiento_ns.dart';
import 'piezas_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

/// El cuadrado "NS" con el nombre al lado.
class MarcaNs extends StatelessWidget {
  const MarcaNs({super.key, this.nombre = 'Nodo Sur'});
  final String nombre;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: ns.ink, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: Text('NS', style: estiloNs(13, peso: FontWeight.w700, color: ns.paper)),
        ),
        const SizedBox(width: 10),
        Text(nombre, style: estiloNs(17, peso: FontWeight.w700, track: -0.02, color: ns.ink)),
      ],
    );
  }
}

class PaginaArranqueNs extends StatelessWidget {
  const PaginaArranqueNs({
    super.key,
    this.titulo,
    this.bajada,
    this.cuerpo = const [],
    this.botones = const [],
    this.alVolver,
    this.derecha,
    this.conMarca = true,
    this.tituloChico = false,
    this.puntos,
    this.pie,
    this.claveTitulo,
    this.cabecera,
  });

  /// Reemplaza la marca / el volver de arriba (el asistente: "Paso N de 3" + barras + "Después").
  final Widget? cabecera;

  /// Clave del texto del título (los tests lo buscan).
  final Key? claveTitulo;

  /// Título grande (40/450). Con [alVolver] pasa a ser el título de página (32) al lado del botón de volver.
  final String? titulo;
  final String? bajada;
  final List<Widget> cuerpo;
  final List<Widget> botones;
  final VoidCallback? alVolver;

  /// Algo a la derecha de la marca ("Saltar", "Después").
  final Widget? derecha;
  final bool conMarca;
  final bool tituloChico;

  /// Puntos de avance (total, actual), encima de los botones.
  final (int, int)? puntos;
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cabecera != null)
                  cabecera!
                else if (alVolver != null)
                  CabeceraSubNs(titulo: titulo ?? '', tamanio: 32, onVolver: alVolver!)
                else if (conMarca)
                  SizedBox(
                    height: 34,
                    child: Row(children: [const MarcaNs(), const Spacer(), ?derecha]),
                  ),
                if (alVolver == null && titulo != null) ...[
                  const SizedBox(height: 14),
                  Text(titulo!, key: claveTitulo, style: tituloNs(tituloChico ? 34 : 40, track: -0.055, altura: 1.02, color: ns.ink)),
                ],
                if (bajada != null) ...[const SizedBox(height: 10), Text(bajada!, style: estiloNs(16, altura: 1.4, color: ns.mute))],
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 0; i < cuerpo.length; i++) ...[if (i > 0) const SizedBox(height: 10), cuerpo[i]],
                    ],
                  ),
                ),
                ?pie,
                if (puntos != null) Padding(padding: const EdgeInsets.only(top: 10, bottom: 14), child: PuntosAvanceNs(total: puntos!.$1, actual: puntos!.$2)),
                for (final b in botones) ...[const SizedBox(height: 8), b],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Los puntitos de la bienvenida: el actual es una barrita oscura.
class PuntosAvanceNs extends StatelessWidget {
  const PuntosAvanceNs({super.key, required this.total, required this.actual});
  final int total;
  final int actual;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == actual ? 26 : 6,
            height: 6,
            decoration: BoxDecoration(color: i == actual ? ns.ink : ns.s2, borderRadius: BorderRadius.circular(3)),
          ),
      ],
    );
  }
}

/// Fila de opción grande con título y detalle (modo de uso, rubro): `s`, radio 28; "marcada" pasa a fondo oscuro.
class OpcionNs extends StatelessWidget {
  const OpcionNs({super.key, required this.titulo, required this.detalle, required this.onTap, this.marcada = false, this.derecha});
  final String titulo;
  final String detalle;
  final VoidCallback onTap;
  final bool marcada;
  final String? derecha;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final texto = marcada ? TokensNs.blanco : ns.ink;
    return Semantics(
      selected: marcada,
      child: PresionNs(
        onTap: onTap,
        etiqueta: titulo,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(color: marcada ? ns.prim : ns.s, borderRadius: BorderRadius.circular(28)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: texto)),
                    const SizedBox(height: 2),
                    Text(detalle, style: estiloNs(13, altura: 1.3, color: texto)),
                  ],
                ),
              ),
              if (derecha != null) ...[const SizedBox(width: 10), Text(derecha!, style: estiloNs(18, peso: FontWeight.w500, color: texto))],
            ],
          ),
        ),
      ),
    );
  }
}

/// Página común del mock: botón de volver con el título, el cuerpo que scrollea y los botones fijos abajo.
class PaginaNs extends StatelessWidget {
  const PaginaNs({super.key, required this.titulo, required this.cuerpo, this.botones = const [], this.sinVolver = false, this.derecha});
  final String titulo;
  final Widget cuerpo;
  final List<Widget> botones;

  /// Sin botón de volver (la pantalla se ofrece como un paso de un flujo).
  final bool sinVolver;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sinVolver)
                  Text(titulo, style: tituloNs(34, track: -0.05, color: ns.ink))
                else
                  CabeceraSubNs(titulo: titulo, derecha: derecha, onVolver: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                Expanded(child: cuerpo),
                for (final b in botones) ...[const SizedBox(height: 8), b],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
