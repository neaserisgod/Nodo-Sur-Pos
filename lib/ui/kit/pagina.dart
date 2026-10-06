// `.page` del mock v4: márgenes de la pantalla y la cabecera (`.phead`: título a la izquierda, acciones a la derecha,
// alineados por abajo). El cuerpo ocupa el resto (`.pbody`).

import 'package:flutter/material.dart';

import 'mov.dart';
import 'paleta.dart';
import 'texto.dart';

/// Margen lateral de la pantalla y de la barra de navegación: 56 px a 1920, menos en ventanas angostas (el piso es
/// 1366×768). La barra y el contenido comparten el borde, como en el mock.
double margenLateral(double anchoVentana) => anchoVentana >= 1700 ? 56 : (anchoVentana >= 1366 ? 32 : 24);

/// Lo que separa el contenido de la barra de navegación: en el mock el contenido arranca en y=100 y la barra termina en
/// 14 + 68 = 82.
const double separacionBajoNavbar = 18;

class PaginaMock extends StatelessWidget {
  const PaginaMock({
    super.key,
    required this.titulo,
    this.acciones = const [],
    this.debajoDelTitulo,
    required this.child,
    this.tituloWidget,
  });

  final String titulo;

  /// `.acts`: botones de la derecha, separados 10.
  final List<Widget> acciones;
  final Widget? debajoDelTitulo;
  final Widget? tituloWidget;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final ancho = MediaQuery.sizeOf(context).width;
    final m = margenLateral(ancho);
    return Padding(
      padding: EdgeInsets.fromLTRB(m, separacionBajoNavbar, m, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tituloWidget ?? Aparecer.revelar(child: Text(titulo, style: Tipos.h1(p.tinta), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ?debajoDelTitulo,
                  ],
                ),
              ),
              if (acciones.isNotEmpty) ...[
                const SizedBox(width: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: acciones,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}
