// Encabezado de las pantallas secundarias (las que se abren encima de una
// pestaña), tal cual el mock (docs/01 §6.3): botón circular de volver (44, fondo
// `s`, flecha ‹) a la izquierda y el título liviano (32/450) a su derecha. Las
// pantallas viejas de la companion que todavía arman un `Scaffold` con
// `appBar:` lo toman de acá y quedan con el mismo aspecto que las del mock.

import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';

class AppBarCompanion extends StatelessWidget implements PreferredSizeWidget {
  const AppBarCompanion({
    super.key,
    required this.titulo,
    this.etiquetaSalida = 'Volver',
    this.acciones = const [],
  });

  final String titulo;

  /// Null no dibuja el botón de volver (pantallas que no se pueden abandonar sin terminar algo).
  final String? etiquetaSalida;

  /// Botones sueltos (actualizar, escanear) que van a la derecha del título.
  final List<Widget> acciones;

  @override
  Size get preferredSize => Size.fromHeight(titulo.length > 22 ? 118 : 86);

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Material(
      color: ns.paper,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 14),
          child: Row(
            children: [
              if (etiquetaSalida != null) ...[
                BotonCircularNs(icono: IconoNs.volver, onTap: () => Navigator.of(context).maybePop(), etiqueta: 'Volver', tamanioIcono: 18, grosor: 2.4),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: tituloNs(32, track: -0.05, altura: 1.02, color: ns.ink))),
              ...acciones,
            ],
          ),
        ),
      ),
    );
  }
}
