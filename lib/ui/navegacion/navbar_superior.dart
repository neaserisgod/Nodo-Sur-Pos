// Navbar superior — dropdown de secciones (Bruno, rediseño 2026-09-25: "la
// navbar quiero que sea un dropdown"): un solo botón que muestra la sección
// activa y abre un menú con el resto. Dejar de mostrar los diez+ íconos a la
// vez le da a la barra de búsqueda (que comparte esta franja) casi todo el
// ancho.
//
// 2026-09-26, sobre un mock de Bruno: el menú dejó de ser el
// `PopupMenuButton` de Material ("parece un conjunto de pegotes con
// animaciones") — ver `_BotonSecciones`.
//
// Reutilizable a propósito: cada pantalla que la use arma su propia lista de
// `ItemNavbarSuperior` y su propia clave activa (`navegacion_gestion.dart`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/tema.dart';
import '../tema/tokens.dart';
import '../tema/iconos.dart';

class ItemNavbarSuperior {
  const ItemNavbarSuperior({required this.clave, required this.etiqueta});

  /// Clave estable de la sección (`secciones_menu.clave`, o `'venta'` /
  /// `'configuracion'` para las dos entradas fijas que no pasan por esa
  /// tabla).
  final String clave;
  final String etiqueta;
}

/// Ícono por clave — mismo mapa que ya tenía la versión anterior de esta
/// barra (y `BarraLateral` antes de eso), sin tocar (decisión puramente
/// visual, no vive en `secciones_menu`).
const Map<String, IconData> _iconosPorClave = {
  'dashboard': IconosPlazoleta.spaceDashboardOutlined,
  'venta': IconosPlazoleta.pointOfSaleOutlined,
  'productos': IconosPlazoleta.inventory2Outlined,
  'stock_proveedor': IconosPlazoleta.factCheckOutlined,
  'proveedores': IconosPlazoleta.localShippingOutlined,
  'separaciones': IconosPlazoleta.callSplitOutlined,
  'historial': IconosPlazoleta.history,
  'configuracion': IconosPlazoleta.settingsOutlined,
};

class NavbarSuperior extends StatelessWidget {
  const NavbarSuperior({
    super.key,
    required this.claveActiva,
    required this.items,
    required this.onSeleccionar,
  });

  final String claveActiva;
  final List<ItemNavbarSuperior> items;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final activo = items.where((i) => i.clave == claveActiva).firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: _BotonSecciones(items: items, claveActiva: claveActiva, activo: activo, onSeleccionar: onSeleccionar),
    );
  }
}

/// Descripción corta de cada sección, debajo del nombre en el menú (mock de
/// Bruno, 2026-09-26).
const Map<String, String> _descripcionPorClave = {
  'dashboard': 'El día y el mes de un vistazo',
  'venta': 'Cobrar y ver tickets',
  'proveedores': 'Productos, precios, stock y pedidos',
  'separaciones': 'Qué apartar, lo vendido y la ganancia',
  'historial': 'Días cerrados y ventas',
  'configuracion': 'Ajustes, respaldo e impresión',
};

const _duracionAbrir = Duration(milliseconds: 220);
const _duracionCerrar = Duration(milliseconds: 150);
const double _altoBoton = 52;
const double _anchoMenu = 320;

/// El botón + el menú de secciones (rediseño 2026-09-26, mock de Bruno:
/// "algo así pero no me gusta que esté separado arriba, y quiero una
/// animación bonita, fluida a la vez que rápida"). Reemplaza al
/// `PopupMenuButton` de Material, que se abría "creciendo" desde el botón y
/// se sentía, textual, "un conjunto de pegotes con animaciones".
///
/// El menú NO queda separado del botón: se dibuja encima de él, arrancando
/// con su misma forma y tamaño, y se despliega hacia abajo — el botón se
/// convierte en la cabecera del menú, una sola pieza. Al abrir, el alto y el
/// ancho crecen juntos con una curva que frena al final, y las secciones
/// aparecen apenas escalonadas; al cerrar, todo vuelve más rápido.
/// Se cierra tocando afuera, con Esc, o al elegir una sección.
class _BotonSecciones extends StatefulWidget {
  const _BotonSecciones({
    required this.items,
    required this.claveActiva,
    required this.activo,
    required this.onSeleccionar,
  });

  final List<ItemNavbarSuperior> items;
  final String claveActiva;
  final ItemNavbarSuperior? activo;
  final ValueChanged<String> onSeleccionar;

  @override
  State<_BotonSecciones> createState() => _BotonSeccionesState();
}

class _BotonSeccionesState extends State<_BotonSecciones> with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _enlace = LayerLink();
  final _claveBoton = GlobalKey();
  late final _animacion = AnimationController(
    vsync: this,
    duration: _duracionAbrir,
    reverseDuration: _duracionCerrar,
  );
  double _anchoBoton = 0;

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  void _abrir() {
    _anchoBoton = (_claveBoton.currentContext?.findRenderObject() as RenderBox?)?.size.width ?? _anchoMenu;
    _portal.show();
    _animacion.forward();
  }

  Future<void> _cerrar() async {
    await _animacion.reverse();
    if (mounted) _portal.hide();
  }

  Future<void> _elegir(String clave) async {
    await _cerrar();
    if (clave != widget.claveActiva) widget.onSeleccionar(clave);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _MenuDesplegado(
        enlace: _enlace,
        animacion: _animacion,
        anchoInicial: _anchoBoton,
        items: widget.items,
        claveActiva: widget.claveActiva,
        activo: widget.activo,
        onCerrar: _cerrar,
        onElegir: _elegir,
      ),
      child: CompositedTransformTarget(
        link: _enlace,
        child: Tooltip(
          message: 'Cambiar de sección',
          waitDuration: const Duration(milliseconds: 900),
          child: KeyedSubtree(
            key: _claveBoton,
            child: _Cabecera(
              activo: widget.activo,
              claveActiva: widget.claveActiva,
              giroFlecha: _animacion,
              onTap: () => _portal.isShowing ? _cerrar() : _abrir(),
              conFondo: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// La insignia "LP", el nombre de la sección activa y la flecha — es el
/// botón cerrado y, sin cambiar de lugar, la cabecera del menú abierto.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.activo,
    required this.claveActiva,
    required this.giroFlecha,
    required this.onTap,
    required this.conFondo,
  });

  final ItemNavbarSuperior? activo;
  final String claveActiva;
  final Animation<double> giroFlecha;
  final VoidCallback onTap;

  /// El botón suelto lleva su píldora; dentro del menú, el fondo es el del
  /// menú mismo.
  final bool conFondo;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
        child: Container(
          height: _altoBoton,
          padding: const EdgeInsets.only(left: 8, right: Espaciado.md),
          decoration: conFondo
              ? BoxDecoration(
                  color: colores.fondoBloque.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(radioControlEscritorio),
                  border: Border.all(color: colores.borde),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colores.acento, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'LP',
                  style: textTheme.titleSmall?.copyWith(color: colores.acentoTexto, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Flexible(
                child: Text(
                  activo?.etiqueta ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: colores.textoPrimario),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              RotationTransition(
                turns: Tween<double>(begin: 0, end: 0.5).animate(
                  CurvedAnimation(parent: giroFlecha, curve: Curves.easeOutCubic),
                ),
                child: Icon(IconosPlazoleta.expandMore, size: 24, color: colores.textoSecundario),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDesplegado extends StatelessWidget {
  const _MenuDesplegado({
    required this.enlace,
    required this.animacion,
    required this.anchoInicial,
    required this.items,
    required this.claveActiva,
    required this.activo,
    required this.onCerrar,
    required this.onElegir,
  });

  final LayerLink enlace;
  final AnimationController animacion;
  final double anchoInicial;
  final List<ItemNavbarSuperior> items;
  final String claveActiva;
  final ItemNavbarSuperior? activo;
  final VoidCallback onCerrar;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    // Una sola curva para todo lo que "crece": arranca rápido y frena al
    // final (se siente ágil sin pegar un salto). Al cerrar, la misma curva
    // al revés en menos tiempo (`reverseDuration`).
    final crecer = CurvedAnimation(parent: animacion, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final secciones = [for (final i in items) if (i.clave != 'configuracion') i];
    final configuracion = items.where((i) => i.clave == 'configuracion').firstOrNull;
    final ancho = anchoInicial > _anchoMenu ? anchoInicial : _anchoMenu;

    Widget aparicion(int indice, Widget hijo) {
      // Cada sección entra un poquito después que la anterior (escalonado
      // corto: todo termina dentro de la misma animación, no se estira).
      final inicio = (0.15 + indice * 0.04).clamp(0.0, 0.7);
      final curva = CurvedAnimation(parent: animacion, curve: Interval(inicio, 1, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: curva,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero).animate(curva),
          child: hijo,
        ),
      );
    }

    var indice = 0;
    final cuerpo = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.md, Espaciado.sm, Espaciado.md, Espaciado.sm),
          child: aparicion(
            indice++,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('La Plazoleta', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('Punto de venta', style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario)),
              ],
            ),
          ),
        ),
        for (final item in secciones)
          aparicion(indice++, _ItemMenu(item: item, activo: item.clave == claveActiva, onTap: () => onElegir(item.clave))),
        if (configuracion != null) ...[
          aparicion(
            indice++,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espaciado.xs, horizontal: Espaciado.md),
              child: Divider(height: 1, color: colores.borde),
            ),
          ),
          aparicion(
            indice++,
            _ItemMenu(
              item: configuracion,
              activo: configuracion.clave == claveActiva,
              onTap: () => onElegir(configuracion.clave),
            ),
          ),
        ],
        const SizedBox(height: Espaciado.sm),
      ],
    );

    return Stack(
      children: [
        // Tocar afuera cierra.
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onCerrar),
        ),
        CompositedTransformFollower(
          link: enlace,
          showWhenUnlinked: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, evento) {
                if (evento is KeyDownEvent && evento.logicalKey == LogicalKeyboardKey.escape) {
                  onCerrar();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AnimatedBuilder(
                animation: crecer,
                builder: (context, hijo) {
                  final t = crecer.value;
                  return Container(
                    key: const Key('menu_secciones'),
                    width: anchoInicial + (ancho - anchoInicial) * t,
                    decoration: BoxDecoration(
                      color: colores.fondoBloque,
                      borderRadius: BorderRadius.circular(radioControlEscritorio),
                      border: Border.all(color: colores.borde),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12 * t),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radioControlEscritorio),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Cabecera(
                            activo: activo,
                            claveActiva: claveActiva,
                            giroFlecha: animacion,
                            onTap: onCerrar,
                            conFondo: false,
                          ),
                          ClipRect(
                            child: Align(alignment: Alignment.topCenter, heightFactor: t, child: hijo),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Material(type: MaterialType.transparency, child: cuerpo),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.item, required this.activo, required this.onTap});

  final ItemNavbarSuperior item;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final descripcion = _descripcionPorClave[item.clave];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.sm, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: colores.acento.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.sm, vertical: Espaciado.sm),
          decoration: BoxDecoration(
            color: activo ? colores.acento.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: activo ? colores.acento : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconosPorClave[item.clave] ?? IconosPlazoleta.circleOutlined,
                  size: 20,
                  color: activo ? colores.acentoTexto : colores.textoSecundario,
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: colores.textoPrimario),
                    ),
                    if (descripcion != null)
                      Text(
                        descripcion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: activo ? colores.acento : colores.textoSecundario,
                        ),
                      ),
                  ],
                ),
              ),
              if (activo) ...[
                const SizedBox(width: Espaciado.sm),
                Icon(IconosPlazoleta.check, size: 20, color: colores.acento),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
