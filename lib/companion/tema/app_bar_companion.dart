// Encabezado de las pantallas secundarias (las que se abren encima de una
// pestaña): titular grande y liviano a la izquierda y una píldora gris para
// salir a la derecha, como en el mock completo del celular. Reemplaza al
// `AppBar` de Material, que dejaba el título chico y sin forma de salir que
// no fuera la flecha de arriba.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';

class AppBarCompanion extends StatelessWidget implements PreferredSizeWidget {
  const AppBarCompanion({
    super.key,
    required this.titulo,
    this.etiquetaSalida = 'Volver',
    this.acciones = const [],
  });

  final String titulo;

  /// Texto de la píldora de salida; null no la dibuja (pantallas que no se
  /// pueden abandonar sin terminar algo).
  final String? etiquetaSalida;

  /// Botones sueltos (actualizar, escanear) que van a la izquierda de la píldora.
  final List<Widget> acciones;

  // Un título largo ("Movimiento de caja") baja a dos renglones al lado de la píldora.
  static const _largoDeUnRenglon = 15;

  @override
  Size get preferredSize => Size.fromHeight(titulo.length > _largoDeUnRenglon ? 124 : 92);

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colores.fondo,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.md, Espaciado.xl, Espaciado.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.headlineLarge),
              ),
              ...acciones,
              if (etiquetaSalida != null) ...[
                const SizedBox(width: Espaciado.sm),
                _PildoraSalida(etiqueta: etiquetaSalida!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PildoraSalida extends StatelessWidget {
  const _PildoraSalida({required this.etiqueta});

  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Material(
      color: colores.fondoBloque,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => Navigator.of(context).maybePop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
            child: Center(
              widthFactor: 1,
              child: Text(
                etiqueta,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: Pesos.fuerte, color: colores.textoPrimario),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
