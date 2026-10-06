// Navbar superior — rediseño "antigravity": las secciones como una fila de pastillas (la activa con fondo gris), igual que
// la barra de la web de Nodo Sur. Desde el rediseño v4 (2026-10-05) tiene tres costados simétricos: "Caja ▾" a la izquierda,
// las pastillas en el centro y la campanita y la tuerca a la derecha. Reemplaza al menú desplegable de un solo
// botón (2026-09-25/26): ahora se ve de un vistazo dónde se puede ir.
//
// Reutilizable a propósito: cada pantalla que la use arma su propia lista de
// `ItemNavbarSuperior` y su propia clave activa (`navegacion_gestion.dart`).
// Ocupa todo el ancho que le den (la fila de pastillas se desplaza si no
// entra), así que quien la use tiene que darle un ancho acotado (`Expanded`).

import 'package:flutter/material.dart';

import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/presionable.dart';
import '../tema/tokens.dart';

class ItemNavbarSuperior {
  const ItemNavbarSuperior({required this.clave, required this.etiqueta});

  /// Clave estable de la sección (`secciones_menu.clave`, o `'venta'` /
  /// `'configuracion'` para las dos entradas fijas que no pasan por esa
  /// tabla).
  final String clave;
  final String etiqueta;
}

/// Alto de la cápsula (`.nav` del mock).
const double altoNavbarSuperior = 68;

/// Margen lateral de la barra y del contenido (56 px a 1920; menos en ventanas más angostas): la barra y las pantallas comparten
/// el mismo borde, como en el mock.
double margenLateralNavbar(double anchoVentana) => anchoVentana >= 1700 ? 56 : (anchoVentana >= 1366 ? 32 : 24);

class NavbarSuperior extends StatelessWidget {
  const NavbarSuperior({
    super.key,
    required this.claveActiva,
    required this.items,
    required this.onSeleccionar,
    this.izquierda,
    this.onAbrirAsistente,
    this.acciones,
    this.busqueda,
    this.buscando = false,
    this.onAbrirBusqueda,
    this.onCerrarBusqueda,
  });

  final String claveActiva;
  final List<ItemNavbarSuperior> items;
  final ValueChanged<String> onSeleccionar;

  /// Lo que va en el costado izquierdo (rediseño v4: el botón "Caja ▾"). Los dos costados ocupan lo mismo, así las secciones
  /// quedan en el centro de la ventana.
  final Widget? izquierda;

  /// Abre el Asistente (Ctrl+K). Null: no se muestra el botón.
  final VoidCallback? onAbrirAsistente;

  /// Lo que va a la derecha ANTES del engranaje (la campanita), para que la tuerca quede siempre en la punta.
  final Widget? acciones;

  /// El campo de búsqueda de la pantalla. Con valor, la barra muestra una lupa y, al abrirla ([buscando]), el campo se
  /// expande desde la derecha hasta tapar las secciones y los botones (El dueño, 2026-10-03); al cerrarla vuelve igual.
  final Widget? busqueda;
  final bool buscando;
  final VoidCallback? onAbrirBusqueda;
  final VoidCallback? onCerrarBusqueda;

  /// Configuración no es una sección más del día a día: va como engranaje a la derecha, no como pastilla.
  static const claveConfiguracion = 'configuracion';

  /// Qué parte del ancho de la barra ocupa la búsqueda abierta.
  static const fraccionBusquedaAbierta = 0.78;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    // Venta primero y azul (como el mock); las demás secciones en el orden que traigan.
    final secciones = [
      ...items.where((i) => i.clave == 'venta'),
      for (final i in items)
        if (i.clave != claveConfiguracion && i.clave != 'venta') i,
    ];
    final hayConfiguracion = items.any((i) => i.clave == claveConfiguracion);
    final conBusqueda = busqueda != null;
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = margenLateralNavbar(ancho);
    return Padding(
      padding: EdgeInsets.fromLTRB(margen, 14, margen, 0),
      child: SizedBox(
        height: altoNavbarSuperior,
        child: LayoutBuilder(
          builder: (context, limites) {
            final compacto = limites.maxWidth < 1500;
            final fila = Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedOpacity(
                      opacity: buscando ? 0 : 1,
                      duration: Animaciones.corta,
                      child: IgnorePointer(ignoring: buscando, child: izquierda ?? const SizedBox.shrink()),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: limites.maxWidth * 0.62),
                  child: AnimatedOpacity(
                    opacity: buscando ? 0 : 1,
                    duration: Animaciones.corta,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final item in secciones)
                            _EnlaceNav(
                              etiqueta: item.etiqueta,
                              esVenta: item.clave == 'venta',
                              activa: item.clave == claveActiva,
                              onTap: () => onSeleccionar(item.clave),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (conBusqueda) ...[
                          _BotonRedondo(
                            llave: const Key('nav_buscar'),
                            tooltip: 'Buscar (Ctrl+F)',
                            icono: IconosPlazoleta.search,
                            onTap: onAbrirBusqueda,
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Con el costado angosto (ventanas de menos de ~1800 px) el asistente queda solo con la lupa: la etiqueta y
                        // el atajo no entran junto a la campanita y el engranaje.
                        if (onAbrirAsistente != null) _BotonAsistente(onTap: onAbrirAsistente!, compacto: compacto),
                        if (acciones != null) Flexible(child: Padding(padding: const EdgeInsets.only(right: 8), child: acciones!)),
                        if (hayConfiguracion)
                          _BotonRedondo(
                            llave: const Key('nav_configuracion'),
                            tooltip: 'Configuración',
                            icono: IconosPlazoleta.settingsOutlined,
                            activo: claveActiva == claveConfiguracion,
                            onTap: () => onSeleccionar(claveConfiguracion),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
            final capsula = DecoratedBox(
              decoration: BoxDecoration(
                color: colores.fondo.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colores.textoPrimario.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: conBusqueda
                    ? LayoutBuilder(
                        builder: (context, interior) => Stack(
                          children: [
                            Positioned.fill(child: fila),
                            // Cerrada mide lo mismo que la lupa y el engranaje juntos y es invisible; abierta crece hacia la izquierda.
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              child: IgnorePointer(
                                ignoring: !buscando,
                                child: AnimatedOpacity(
                                  opacity: buscando ? 1 : 0,
                                  duration: Animaciones.corta,
                                  child: AnimatedContainer(
                                    key: const Key('nav_busqueda_abierta'),
                                    duration: Animaciones.media,
                                    curve: Animaciones.curva,
                                    width: buscando ? interior.maxWidth * fraccionBusquedaAbierta : 88,
                                    alignment: Alignment.center,
                                    child: Row(
                                      children: [
                                        Expanded(child: busqueda!),
                                        const SizedBox(width: Espaciado.xs),
                                        _BotonRedondo(
                                          llave: const Key('nav_cerrar_busqueda'),
                                          tooltip: 'Cerrar búsqueda (Esc)',
                                          icono: IconosPlazoleta.close,
                                          onTap: onCerrarBusqueda,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : fila,
              ),
            );
            return capsula;
          },
        ),
      ),
    );
  }
}

/// "Asistente · Ctrl+K" (mock): píldora azul suave con la chispa, el nombre y el atajo.
class _BotonAsistente extends StatelessWidget {
  const _BotonAsistente({required this.onTap, this.compacto = false});

  final VoidCallback onTap;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final azul = azulMarca;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Asistente (Ctrl+K)',
        child: Semantics(
          button: true,
          label: 'Asistente (Ctrl+K)',
          child: Presionable(
            key: const Key('nav_asistente'),
            radio: 999,
            onTap: onTap,
            color: context.azulSuaveFondo,
            child: Container(
              height: Medidas.alturaControl,
              constraints: const BoxConstraints(minWidth: Medidas.alturaControl),
              padding: EdgeInsets.symmetric(horizontal: compacto ? 15 : 18),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 17, color: azul),
                  if (!compacto) ...[
                    const SizedBox(width: 8),
                    Text('Asistente', style: TextStyle(fontSize: 15, fontWeight: Pesos.medium, color: azul)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: azul.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Text('Ctrl+K', style: TextStyle(fontSize: 12, fontWeight: Pesos.medium, color: azul, letterSpacing: 0.24, height: 1.3)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una sección de la barra (`.nl` del mock): texto sin fondo; al pasar el mouse o estar activa se tiñe de gris. Venta es la píldora azul.
class _EnlaceNav extends StatefulWidget {
  const _EnlaceNav({required this.etiqueta, required this.activa, required this.onTap, this.esVenta = false});

  final String etiqueta;
  final bool esVenta;
  final bool activa;
  final VoidCallback onTap;

  @override
  State<_EnlaceNav> createState() => _EnlaceNavState();
}

class _EnlaceNavState extends State<_EnlaceNav> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final activa = widget.activa;
    final Color fondo = widget.esVenta
        ? (activa || _encima ? azulMarcaOscuro : azulMarca)
        : (activa || _encima ? colores.fondoBloque : Colors.transparent);
    final Color texto = widget.esVenta ? Colors.white : (activa ? colores.textoPrimario : (_encima ? colores.textoPrimario : colores.textoSecundario));
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Padding(
        padding: EdgeInsets.only(right: widget.esVenta ? 10 : 4),
        child: Presionable(
          radio: 999,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Animaciones.corta,
            curve: Animaciones.curva,
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: widget.esVenta ? 24 : 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
            child: AnimatedDefaultTextStyle(
              duration: Animaciones.corta,
              style: TextStyle(
                fontFamily: familiaTipografica,
                fontSize: 16,
                fontWeight: (activa || widget.esVenta) ? Pesos.medium : Pesos.intermedio,
                color: texto,
              ),
              child: Text(widget.etiqueta, maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Círculo de 46 px gris (`.ci` del mock): la lupa, la campanita y la tuerca.
class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.llave,
    required this.tooltip,
    required this.icono,
    required this.onTap,
    this.activo = false,
  });

  final Key llave;
  final String tooltip;
  final IconData icono;
  final VoidCallback? onTap;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Presionable(
          key: llave,
          radio: 999,
          onTap: onTap,
          color: activo ? colores.textoPrimario : colores.fondoBloque,
          child: SizedBox(
            width: Medidas.alturaControl,
            height: Medidas.alturaControl,
            child: IconoPlz(icono, size: 22, color: activo ? colores.fondo : colores.textoPrimario),
          ),
        ),
      ),
    );
  }
}
