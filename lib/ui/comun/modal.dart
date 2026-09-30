// El único diálogo de la app: centrado, ancho máximo `anchoMaximoContenido`,
// título arriba, botones abajo a la derecha. Reemplaza cada `AlertDialog`
// armado a mano (alta rápida, pagar a proveedor, renombrar usuario/medio de
// pago, etc.) — todos comparten esta misma estructura, solo cambia el
// contenido y los botones.
//
// Remake de la estética (El dueño, 2026-09-19): vidrio esmerilado (blur +
// relleno translúcido + borde + sombra), mismo tratamiento que
// `mostrarHojaVidrio` de la companion, adaptado a diálogo centrado en vez
// de hoja inferior — el escritorio no tiene affordance de "abajo" ni gesto
// de arrastrar para cerrar. La API pública (`mostrarModal`, `Modal`) no
// cambia, así que ningún llamador existente se toca.
//
// El cierre con Esc se fuerza a mano con `CallbackShortcuts` en vez de
// confiar en el comportamiento por defecto de `Dialog`: así queda
// garantizado sin depender de qué versión de Flutter lo trae de fábrica.
//
// `mostrarModal` es la única forma de abrir esto: fija el velo de fondo
// (`_colorVelo`) en un solo lugar. `showDialog` sin `barrierColor` explícito
// usa `Colors.black54` siempre — mismo número en los dos temas, pero el
// mismo negro pesa distinto según lo que tiene atrás: sobre el canvas claro
// apenas se nota; sobre el oscuro lo funde casi entero (corrección
// post-aprobación del kit, el dueño). Un gris neutro en vez de negro puro
// achica esa diferencia en los dos sentidos a la vez.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/iconos.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';

const Color _colorVelo = Color(0x99808080);

/// Único punto de entrada para abrir un [Modal] — fija el velo de fondo para
/// que ningún llamador tenga que acordarse de pasarlo.
Future<T?> mostrarModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: _colorVelo,
    builder: builder,
  );
}

class Modal extends StatelessWidget {
  const Modal({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.contenido,
    required this.botones,
    this.ancho = Medidas.anchoMaximoContenido,
    this.alturaMaxima,
  });

  final String titulo;

  /// Una línea de contexto bajo el título ("Total de la venta $ 16.950").
  final String? subtitulo;
  final Widget contenido;

  /// De izquierda a derecha; el último suele ser la acción de confirmar.
  final List<Widget> botones;

  /// Ancho propio para el contenido de este modal en particular (ver
  /// `Medidas.anchoModalCierre` para el caso que lo necesita). El default
  /// es el mismo de siempre, así que ningún llamador existente cambia.
  final double ancho;

  /// Sin fijar (default): el modal se ajusta al alto de `contenido`, como
  /// siempre. Con un valor, acota el alto del diálogo entero y deja que
  /// `contenido` scrollee adentro — necesario para el cierre de caja, que
  /// no entra completo en pantallas más chicas que 1920×1080.
  final double? alturaMaxima;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final restricciones = alturaMaxima == null
        ? BoxConstraints(maxWidth: ancho)
        : BoxConstraints(maxWidth: ancho, maxHeight: alturaMaxima!);
    return FocusScope(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Dialog(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          backgroundColor: colores.fondoBloque,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioSuperficieEscritorio + 4)),
          child: ConstrainedBox(
            constraints: restricciones,
            // "Lenguaje de diseño" (El dueño, 2026-09-26): diálogo opaco con
            // una sombra suave para despegarlo del velo, en vez del vidrio
            // esmerilado (blur + relleno translúcido) de antes — el lenguaje
            // nuevo es plano, y el blur dejaba el diálogo grisáceo.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radioSuperficieEscritorio + 4),
              child: DecoratedBox(
                decoration: BoxDecoration(color: colores.fondoBloque),
                child: Container(
                  decoration: const BoxDecoration(),
                  // `Material` transparente propio: sin esto, cualquier
                  // `ListTile`/`InkWell` de `contenido` pinta su ink en el
                  // `Material` del `Dialog`, que queda TAPADO por este
                  // `Container` decorado — Flutter lo detecta y tira un
                  // assert en tests (`ListTile background color or ink
                  // splashes may be invisible`). Este `Material` de acá es
                  // el ancestro más cercano, así el ink pinta donde
                  // corresponde.
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.all(Espaciado.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "Lenguaje de diseño" (mocks `Dialogos*`): título
                          // con una línea de contexto y una cruz para cerrar
                          // con el mouse — Esc ya lo hacía, pero no se veía.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(titulo, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: Pesos.fuerte)),
                                    if (subtitulo != null)
                                      Text(
                                        subtitulo!,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                icon: const Icon(IconosPlazoleta.close),
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: Espaciado.lg),
                          // Sin alto fijo, el contenido scrollea si no entra en la
                          // ventana (a 1366×768 un diálogo con teclado numérico
                          // o varias filas de chips puede no entrar).
                          alturaMaxima == null ? Flexible(child: SingleChildScrollView(child: contenido)) : Flexible(child: contenido),
                          const SizedBox(height: Espaciado.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              for (var i = 0; i < botones.length; i++) ...[
                                if (i != 0) const SizedBox(width: Espaciado.sm),
                                botones[i],
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
