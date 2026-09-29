// Navbar flotante, ahora de vidrio de verdad (Bruno, 2026-09-18: "un poco de
// glassmorfismo estilo Apple, pero reversionado para Android"). Apple usa el
// vidrio esmerilado en elementos FLOTANTES — la barra de pestañas, el centro
// de control, una hoja modal — nunca en el contenido en sí; el mismo
// criterio se aplica acá: la navbar (lo único que flota sobre contenido de
// verdad) se vuelve vidrio (`BackdropFilter`, desenfoca lo que pasa
// scrolleando detrás), pero las tarjetas de "Inicio" siguen con el lenguaje
// bold flat de color sólido — mezclar vidrio y color-blocking en todos
// lados se pisaría, no se sumaría.
//
// La barra de antes iba pegada a los tres bordes de la pantalla, igual que
// cualquier `BottomNavigationBar` de fábrica; sigue flotando con margen y
// esquinas redondas del todo, con una sombra suave propia (la única
// excepción a "sin sombra" de toda la companion, junto con el resplandor
// del botón central: acá la sombra cumple un rol real —separar una pieza
// flotante del contenido que tiene debajo—, no decoración). El botón
// circular del medio (`BotonEscanerCompanion`) se sigue dibujando medio
// afuera de la barra.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'tema/resplandor.dart';
import 'tema/tema_companion.dart';
import '../ui/tema/iconos.dart';

class NavbarCompanion extends StatelessWidget {
  const NavbarCompanion({
    super.key,
    required this.indice,
    required this.onSeleccionar,
    required this.botonCentral,
  });

  /// 0 Inicio, 1 Productos, 2 Historial, 3 Gestión — el escáner no tiene
  /// índice propio: no es una pestaña, es una acción que abre una pantalla
  /// nueva.
  final int indice;
  final ValueChanged<int> onSeleccionar;

  /// El botón circular del medio, ya armado por quien use esta barra
  /// (`BotonEscanerCompanion`) — la navbar solo lo posiciona.
  final Widget botonCentral;

  static const double _alturaBarra = 68;
  static const double diametroBoton = 56;
  static const double _margenLateral = 20;
  static const double _margenInferior = 16;

  /// Cuánto padding inferior necesita el contenido de cada pestaña para no
  /// quedar tapado por la barra — Bruno, 2026-09-18: "la navbar no parece
  /// flotar, tiene un recuadro abajo". La causa real: `Scaffold` reservaba
  /// su propio layout para `bottomNavigationBar` con el fondo de pantalla
  /// parejo detrás, así que el margen "flotante" de esta barra en realidad
  /// flotaba sobre una franja vacía del mismo color, no sobre contenido de
  /// verdad — se leía como un recuadro sólido, no como algo suspendido en
  /// el aire. `PantallaMenuCompanion` ahora usa `extendBody: true` (el
  /// `PageView` pasa POR DEBAJO de la barra de verdad) y cada pestaña
  /// agrega este padding a su lista/scroll para que el último elemento
  /// siga siendo alcanzable sin quedar oculto.
  static const double espacioReservado =
      _alturaBarra + _margenInferior + Espaciado.sm;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final inferior = MediaQuery.of(context).padding.bottom;
    final margenInferiorReal = _margenInferior + inferior;
    return SizedBox(
      height: _alturaBarra + diametroBoton / 2 + margenInferiorReal,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // `RepaintBoundary` alrededor de TODA la píldora (Bruno,
          // 2026-09-19: "revisa bien el tema rendimiento") — `BackdropFilter`
          // repinta esta capa en cada frame mientras el contenido de atrás
          // scrollea (tiene que volver a desenfocar lo que cambió); sin este
          // límite explícito, ese repintado puede arrastrar de vuelta al
          // resto del árbol (el botón central de al lado, con su propio
          // spinner) en vez de quedar aislado en su propia capa compuesta.
          RepaintBoundary(
            child: Container(
              height: _alturaBarra,
              margin: EdgeInsets.fromLTRB(
                _margenLateral,
                0,
                _margenLateral,
                margenInferiorReal,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                // Borde de un solo píxel, más claro que el fondo — la señal de
                // "esto es un borde de vidrio" cuando lo que hay detrás varía
                // de color al scrollear (sin esto, un vidrio sobre un fondo
                // parejo es indistinguible de una superficie sólida cualquiera).
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              // `ClipRRect` recorta el blur a la forma de la píldora — sin
              // esto, `BackdropFilter` desenfoca en un rectángulo entero,
              // ignorando el radio del borde.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  // Sigma 24 → 16 (Bruno, 2026-09-19, mismo pedido de
                  // rendimiento): el costo de `BackdropFilter` escala con el
                  // radio del desenfoque — 16 sigue leyéndose como vidrio
                  // esmerilado real, con bastante menos trabajo por frame
                  // mientras se scrollea detrás.
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    // El tinte semitransparente ES el vidrio — sin esto,
                    // `BackdropFilter` solo desenfoca lo de atrás y no queda
                    // ninguna superficie propia sobre la que dibujar los
                    // íconos.
                    color: colores.fondoBloque.withValues(alpha: 0.55),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Item(
                            icono: IconosPlazoleta.storefrontOutlined,
                            etiqueta: 'Inicio',
                            activo: indice == 0,
                            onTap: () => onSeleccionar(0),
                          ),
                        ),
                        Expanded(
                          child: _Item(
                            icono: IconosPlazoleta.inventory2Outlined,
                            etiqueta: 'Productos',
                            activo: indice == 1,
                            onTap: () => onSeleccionar(1),
                          ),
                        ),
                        // Hueco para el botón flotante.
                        const SizedBox(width: diametroBoton),
                        Expanded(
                          child: _Item(
                            icono: IconosPlazoleta.listAltOutlined,
                            etiqueta: 'Historial',
                            activo: indice == 2,
                            onTap: () => onSeleccionar(2),
                          ),
                        ),
                        Expanded(
                          child: _Item(
                            icono: IconosPlazoleta.settingsOutlined,
                            etiqueta: 'Gestión',
                            activo: indice == 3,
                            onTap: () => onSeleccionar(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: _alturaBarra / 2 + margenInferiorReal - diametroBoton / 2,
            child: RepaintBoundary(child: botonCentral),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final color = activo ? colores.acento : colores.textoSecundario;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              // "Dark glass premium" (Bruno, rediseño 2026-09-25): antes sin
              // curva explícita (default `Curves.linear`) — se le suma el
              // snap de `curvaSpring`, mismo criterio que `NavbarSuperior`.
              duration: const Duration(milliseconds: 160),
              curve: Animaciones.curvaSpring,
              padding: const EdgeInsets.symmetric(
                horizontal: EspacioCompanion.md,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: activo
                    ? colores.acento.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(radioControlCompanion),
                // Halo neón en la pestaña activa (Bruno, 2026-09-19:
                // "cyberpunk me vuela la gorra") — sutil a propósito, es una
                // pastilla chica que ya vive sobre vidrio esmerilado.
                boxShadow: activo
                    ? resplandorNeon(
                        colores.acento,
                        alpha: 0.4,
                        radio: 10,
                        offset: const Offset(0, 2),
                      )
                    : null,
              ),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(height: 3),
            Text(
              etiqueta,
              style: TextStyle(
                fontSize: 11,
                fontWeight: activo ? Pesos.medium : Pesos.regular,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
