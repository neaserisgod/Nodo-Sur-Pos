// Navbar superior — rediseño "antigravity": la marca a la izquierda y las
// secciones como una fila de pastillas (la activa con fondo gris), igual que
// la barra de la web de Nodo Sur. Reemplaza al menú desplegable de un solo
// botón (2026-09-25/26): ahora se ve de un vistazo dónde se puede ir.
//
// Reutilizable a propósito: cada pantalla que la use arma su propia lista de
// `ItemNavbarSuperior` y su propia clave activa (`navegacion_gestion.dart`).
// Ocupa todo el ancho que le den (la fila de pastillas se desplaza si no
// entra), así que quien la use tiene que darle un ancho acotado (`Expanded`).

import 'package:flutter/material.dart';

import '../../companion/kit/iconos_ns.dart';
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

/// Ícono de trazo de cada sección (mock: los mismos del celular). Una clave que no está acá (sección nueva) va sin ícono.
IconoNs? iconoDeSeccion(String clave) => switch (clave) {
  'dashboard' => IconoNs.inicio,
  'venta' => IconoNs.carrito,
  'proveedores' => IconoNs.camion,
  'separaciones' => IconoNs.billetera,
  'historial' => IconoNs.portapapeles,
  'encargues' => IconoNs.calendario,
  _ => null,
};

/// Alto de la barra: la búsqueda que la acompaña usa el mismo.
const double altoNavbarSuperior = 52;

class NavbarSuperior extends StatelessWidget {
  const NavbarSuperior({
    super.key,
    required this.claveActiva,
    required this.items,
    required this.onSeleccionar,
    this.acciones,
    this.busqueda,
    this.buscando = false,
    this.onAbrirBusqueda,
    this.onCerrarBusqueda,
  });

  final String claveActiva;
  final List<ItemNavbarSuperior> items;
  final ValueChanged<String> onSeleccionar;

  /// Lo que va a la derecha después del engranaje (en Venta, las acciones de caja).
  final Widget? acciones;

  /// El campo de búsqueda de la pantalla. Con valor, la barra muestra una lupa y, al abrirla ([buscando]), el campo se
  /// expande desde la derecha hasta tapar las pastillas y los botones (El dueño, 2026-10-03); al cerrarla vuelve igual.
  final Widget? busqueda;
  final bool buscando;
  final VoidCallback? onAbrirBusqueda;
  final VoidCallback? onCerrarBusqueda;

  /// Configuración no es una sección más del día a día: va como engranaje a la derecha, no como pastilla
  /// (El dueño, 2026-10-03: "simplificá lo más posible la navbar").
  static const claveConfiguracion = 'configuracion';

  /// Qué parte del ancho de la barra ocupa la búsqueda abierta: desde donde pueden empezar las pastillas (que van
  /// centradas en el 56% del medio) hasta el borde derecho de los botones.
  static const fraccionBusquedaAbierta = 0.78;

  @override
  Widget build(BuildContext context) {
    final secciones = [for (final i in items) if (i.clave != claveConfiguracion) i];
    final hayConfiguracion = secciones.length != items.length;
    final conBusqueda = busqueda != null;
    // Las secciones van centradas en la ventana (El dueño, 2026-10-03: "quiero que esté al centro") y sin la marca: el
    // nombre del comercio ya está en la barra de la ventana. Los dos costados ocupan lo mismo, así el centro de las
    // pastillas es el de la ventana; si no entran, se desplazan.
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: SizedBox(
        height: altoNavbarSuperior,
        child: LayoutBuilder(
          builder: (context, limites) {
            final fila = Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: limites.maxWidth * 0.56),
                  child: AnimatedOpacity(
                    opacity: buscando ? 0 : 1,
                    duration: Animaciones.corta,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      // Las pastillas van sobre una cápsula gris, como la barra del mock.
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: context.colores.fondoBloque, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final item in secciones)
                              _Pastilla(
                                etiqueta: item.etiqueta,
                                icono: iconoDeSeccion(item.clave),
                                esVenta: item.clave == 'venta',
                                activa: item.clave == claveActiva,
                                onTap: () => onSeleccionar(item.clave),
                              ),
                          ],
                        ),
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
                        if (conBusqueda)
                          _BotonRedondo(
                            llave: const Key('nav_buscar'),
                            tooltip: 'Buscar (Ctrl+F)',
                            icono: IconosPlazoleta.search,
                            onTap: onAbrirBusqueda,
                          ),
                        if (hayConfiguracion)
                          _BotonRedondo(
                            llave: const Key('nav_configuracion'),
                            tooltip: 'Configuración',
                            icono: IconosPlazoleta.settingsOutlined,
                            activo: claveActiva == claveConfiguracion,
                            onTap: () => onSeleccionar(claveConfiguracion),
                          ),
                        if (acciones != null) ...[
                          const SizedBox(width: Espaciado.sm),
                          Flexible(child: acciones!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
            if (!conBusqueda) return fila;
            return Stack(
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
                        width: buscando ? limites.maxWidth * fraccionBusquedaAbierta : 88,
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
            );
          },
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.etiqueta, required this.activa, required this.onTap, this.icono, this.esVenta = false});

  final String etiqueta;
  final IconoNs? icono;

  /// Venta es el botón azul de marca (más oscuro cuando es la pantalla activa), como "Vender" del celular.
  final bool esVenta;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final Color fondo = esVenta
        ? (activa ? azulMarcaOscuro : azulMarca)
        : (activa ? context.azulSuaveFondo : colores.fondoBloque.withValues(alpha: 0));
    final Color texto = esVenta ? Colors.white : (activa ? context.azulSuaveTexto : colores.textoSecundario);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Presionable(
        radio: 999,
        onTap: onTap,
        // El fondo de la activa aparece y se va con un fundido corto en vez de saltar.
        child: AnimatedContainer(
          duration: Animaciones.corta,
          curve: Animaciones.curva,
          height: Medidas.alturaControl,
          padding: EdgeInsets.only(left: icono == null ? Espaciado.lg + 2 : Espaciado.lg, right: Espaciado.lg + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                IconoNsWidget(icono!, tamanio: 20, color: texto, grosor: 2.1),
                const SizedBox(width: Espaciado.sm),
              ],
              AnimatedDefaultTextStyle(
                duration: Animaciones.corta,
                style: textTheme.bodyMedium!.copyWith(
                  fontWeight: (activa || esVenta) ? Pesos.fuerte : Pesos.medium,
                  color: texto,
                  letterSpacing: -0.16,
                ),
                child: Text(etiqueta, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.llave, required this.tooltip, required this.icono, required this.onTap, this.activo = false});

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
          color: activo ? colores.fondoBloque : null,
          child: SizedBox(
            width: Medidas.alturaControl,
            height: Medidas.alturaControl,
            child: IconoPlz(icono, size: 22, color: activo ? colores.textoPrimario : colores.textoSecundario),
          ),
        ),
      ),
    );
  }
}
