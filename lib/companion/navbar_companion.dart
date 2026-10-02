// Navbar inferior del rediseño "antigravity": barra plana de borde a borde,
// fondo igual al de la pantalla y una línea fina arriba; el ítem activo se
// marca con una píldora gris y el botón del medio (`BotonEscanerCompanion`)
// es un círculo de tinta que sobresale de la barra.

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
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

  static const double _alturaBarra = 64;
  static const double diametroBoton = 56;
  static const double _margenInferior = 4;

  /// Cuánto padding inferior necesita el contenido de cada pestaña para no
  /// quedar tapado por la barra — El dueño, 2026-09-18: "la navbar no parece
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
      height: _alturaBarra + margenInferiorReal + diametroBoton / 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // `RepaintBoundary` para que el repintado de la barra no arrastre al botón central.
          RepaintBoundary(
            child: Container(
              height: _alturaBarra + margenInferiorReal,
              padding: EdgeInsets.only(bottom: margenInferiorReal),
              decoration: BoxDecoration(
                color: colores.fondo,
                border: Border(top: BorderSide(color: colores.borde)),
              ),
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
                  const SizedBox(width: diametroBoton + 12),
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
          Positioned(
            bottom: _alturaBarra / 2 + margenInferiorReal - diametroBoton / 2 + 6,
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
    final color = activo ? colores.textoPrimario : colores.textoTenue;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Animaciones.curvaSpring,
              padding: const EdgeInsets.symmetric(
                horizontal: EspacioCompanion.lg,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: activo ? colores.fondoBloque : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
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
