// Barra de navegación del mock v4 (`.nav`, `#hdr`, `.mega`, `.mscrim` en `p1_head.html`; `navHtml` en `p3_core.js`),
// hecha desde cero (2026-10-06, el dueño: "fidelidad visual 1:1 con el mock").
//
// Una cápsula flotante de 68 px con tres costados: "Caja ▾" a la izquierda; en el centro Venta (la píldora azul con el
// carrito) y las secciones como enlaces de texto, las que tienen más de una pantalla con un chevron que abre su mega-menú
// al pasar el mouse; a la derecha el Asistente (Ctrl+K), la campanita y la tuerca de Configuración.
//
// Con [child], la barra arma toda la pantalla: el contenido abajo, el velo y el mega-menú en el medio y la cápsula
// arriba de todo (el mega-menú sale DE ATRÁS de la cápsula, como en el mock). Sin [child] es solo la cápsula.
//
// Ctrl+F en una pantalla con búsqueda propia ([busqueda]) abre el campo dentro de la cápsula (`.sbar` del mock): las
// secciones se desvanecen y el campo ocupa la barra. El mock no tiene lupa a la vista: se llega con el teclado.

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../kit/kit.dart';

class ItemNavbarSuperior {
  const ItemNavbarSuperior({required this.clave, required this.etiqueta});

  /// Clave estable de la sección (`secciones_menu.clave`, o `'venta'` / `'configuracion'` para las dos entradas fijas).
  final String clave;
  final String etiqueta;
}

/// Alto de la cápsula (`.nav`).
const double altoNavbarSuperior = 68;

/// Donde termina la barra: 14 de margen arriba + 68 de cápsula.
const double finNavbarSuperior = 14 + altoNavbarSuperior;

/// Margen lateral de la barra y del contenido (el mismo que `.page`).
double margenLateralNavbar(double anchoVentana) => margenLateral(anchoVentana);

/// Una fila de un mega-menú: ícono, nombre y una pista chica a la derecha. [destino] es lo que se le pasa a
/// `onSeleccionar` ("historial/cierres").
class ItemMegaMenu {
  const ItemMegaMenu({required this.icono, required this.titulo, required this.destino, this.pista});
  final Ic icono;
  final String titulo;
  final String destino;
  final String? pista;
}

class MegaMenu {
  const MegaMenu({required this.titulo, required this.texto, required this.items});
  final String titulo;
  final String texto;
  final List<ItemMegaMenu> items;
}

/// Los mega-menús del mock (`MEGA` en `p3_core.js`). Comparar precios solo con su módulo prendido.
Map<String, MegaMenu> megaMenusDeLaApp(ModulosNegocio modulos) => {
      'proveedores': MegaMenu(
        titulo: 'Proveedores y productos',
        texto: 'Lista, cuenta corriente, precios por ganancia y stock.',
        items: [
          const ItemMegaMenu(icono: Ic.truck, titulo: 'Proveedores y productos', destino: 'proveedores'),
          const ItemMegaMenu(icono: Ic.list, titulo: 'Contar stock por góndola', destino: 'proveedores/conteo', pista: 'conteo físico'),
          if (modulos.estaActivo(Modulo.compararPrecios))
            const ItemMegaMenu(icono: Ic.percent, titulo: 'Comparar precios', destino: 'proveedores/comparar'),
        ],
      ),
      'historial': const MegaMenu(
        titulo: 'Lo que pasó en la caja',
        texto: 'Ventas, movimientos y cierres; editá o anulá lo ya cobrado.',
        items: [
          ItemMegaMenu(icono: Ic.clip, titulo: 'Ventas', destino: 'historial'),
          ItemMegaMenu(icono: Ic.swap, titulo: 'Movimientos', destino: 'historial/movimientos'),
          ItemMegaMenu(icono: Ic.lock, titulo: 'Cierres', destino: 'historial/cierres', pista: 'con detalle del día'),
          ItemMegaMenu(icono: Ic.cal, titulo: 'Cargar un día histórico', destino: 'historial/carga'),
        ],
      ),
    };

class NavbarSuperior extends StatefulWidget {
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
    this.child,
  });

  final String claveActiva;
  final List<ItemNavbarSuperior> items;

  /// Recibe la clave de una sección ("historial") o un destino de un mega-menú ("historial/cierres").
  final ValueChanged<String> onSeleccionar;

  /// El botón "Caja ▾".
  final Widget? izquierda;

  /// Abre el Asistente (Ctrl+K). Null: no se muestra el botón.
  final VoidCallback? onAbrirAsistente;

  /// Lo que va a la derecha antes de la tuerca (la campanita).
  final Widget? acciones;

  /// El campo de búsqueda propio de la pantalla; [buscando] lo muestra adentro de la cápsula.
  final Widget? busqueda;
  final bool buscando;

  /// Se conservan por compatibilidad con quien abre la búsqueda por su cuenta (Ctrl+F lo maneja quien arma la barra).
  final VoidCallback? onAbrirBusqueda;
  final VoidCallback? onCerrarBusqueda;

  /// El contenido de la pantalla, debajo de la barra.
  final Widget? child;

  /// Configuración no es una sección más del día a día: va como tuerca a la derecha.
  static const claveConfiguracion = 'configuracion';

  @override
  State<NavbarSuperior> createState() => _NavbarSuperiorState();
}

class _NavbarSuperiorState extends State<NavbarSuperior> {
  String? _megaAbierto;
  Timer? _abrirT;
  Timer? _cerrarT;

  @override
  void dispose() {
    _abrirT?.cancel();
    _cerrarT?.cancel();
    super.dispose();
  }

  void _pedirAbrir(String clave) {
    _cerrarT?.cancel();
    _abrirT?.cancel();
    // `mouseenter` + 70 ms del mock: pasar por encima sin querer no abre nada.
    _abrirT = Timer(ms(70), () {
      if (mounted && _megaAbierto != clave) setState(() => _megaAbierto = clave);
    });
  }

  void _pedirCerrar() {
    _abrirT?.cancel();
    _cerrarT?.cancel();
    _cerrarT = Timer(ms(150), _cerrarYa);
  }

  void _seguirAbierto() => _cerrarT?.cancel();

  void _cerrarYa() {
    _abrirT?.cancel();
    _cerrarT?.cancel();
    if (mounted && _megaAbierto != null) setState(() => _megaAbierto = null);
  }

  void _ir(String destino) {
    _cerrarYa();
    widget.onSeleccionar(destino);
  }

  @override
  Widget build(BuildContext context) {
    final capsula = ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) => _capsula(context, megaMenusDeLaApp(modulos)),
    );
    final ancho = MediaQuery.sizeOf(context).width;
    final m = margenLateral(ancho);
    final barra = Padding(padding: EdgeInsets.fromLTRB(m, 14, m, 0), child: SizedBox(height: altoNavbarSuperior, child: capsula));
    if (widget.child == null) return barra;

    final mega = ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) {
        final megas = megaMenusDeLaApp(modulos);
        final abierto = _megaAbierto == null ? null : megas[_megaAbierto];
        return _CapaMega(
          menu: abierto,
          clave: _megaAbierto,
          onEnter: _seguirAbierto,
          onExit: _pedirCerrar,
          onElegir: _ir,
        );
      },
    );
    final abierto = _megaAbierto != null;
    return Stack(
      children: [
        Positioned.fill(top: finNavbarSuperior, child: widget.child!),
        // `.mscrim`: velo suave con desenfoque detrás del mega-menú; tocarlo lo cierra.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !abierto,
            child: GestureDetector(
              onTap: _cerrarYa,
              child: AnimatedOpacity(
                opacity: abierto ? 1 : 0,
                duration: ms(250),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: abierto ? 2 : 0, sigmaY: abierto ? 2 : 0),
                  child: const ColoredBox(color: Color(0x1F121317)),
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, child: mega),
        Positioned(left: 0, right: 0, top: 0, child: barra),
      ],
    );
  }

  Widget _capsula(BuildContext context, Map<String, MegaMenu> megas) {
    final p = context.p;
    final secciones = [
      ...widget.items.where((i) => i.clave == 'venta'),
      for (final i in widget.items)
        if (i.clave != NavbarSuperior.claveConfiguracion && i.clave != 'venta') i,
    ];
    final hayConfiguracion = widget.items.any((i) => i.clave == NavbarSuperior.claveConfiguracion);
    final levantada = _megaAbierto != null;
    final buscando = widget.buscando && widget.busqueda != null;

    return LayoutBuilder(
      builder: (context, c) {
        final compacta = c.maxWidth < 1560;
        final centro = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in secciones)
              item.clave == 'venta'
                  ? _BotonVenta(
                      etiqueta: item.etiqueta,
                      activa: widget.claveActiva == 'venta',
                      onTap: () => _ir('venta'),
                      onEnter: _pedirCerrar,
                    )
                  : _EnlaceNav(
                      etiqueta: item.etiqueta,
                      activa: widget.claveActiva == item.clave,
                      conMega: megas.containsKey(item.clave),
                      abierto: _megaAbierto == item.clave,
                      onTap: () => _ir(item.clave),
                      onEnter: megas.containsKey(item.clave) ? () => _pedirAbrir(item.clave) : _pedirCerrar,
                      onExit: megas.containsKey(item.clave) ? _pedirCerrar : null,
                      onFoco: megas.containsKey(item.clave) ? () => setState(() => _megaAbierto = item.clave) : null,
                    ),
          ],
        );
        final derecha = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onAbrirAsistente != null) ...[_BotonAsistente(onTap: widget.onAbrirAsistente!, compacto: compacta), const SizedBox(width: 8)],
            if (widget.acciones != null) ...[widget.acciones!, const SizedBox(width: 8)],
            if (hayConfiguracion)
              BotonCirculo(
                key: const Key('nav_configuracion'),
                icono: Ic.gear,
                etiqueta: 'Configuración',
                grosor: 1.9,
                activo: widget.claveActiva == NavbarSuperior.claveConfiguracion,
                onTap: () => _ir(NavbarSuperior.claveConfiguracion),
              ),
          ],
        );
        final fila = Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Desvanecer(oculto: buscando, child: widget.izquierda ?? const SizedBox.shrink()),
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * .64),
              child: _Desvanecer(
                oculto: buscando,
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: centro),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _Desvanecer(
                  oculto: buscando,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: derecha),
                ),
              ),
            ),
          ],
        );
        return AnimatedContainer(
          duration: ms(300),
          decoration: BoxDecoration(
            color: levantada ? p.navbg2 : p.navbg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.navline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: widget.busqueda == null
                    ? fila
                    : Stack(
                        children: [
                          Positioned.fill(child: fila),
                          // `.sbar`: el campo de la pantalla adentro de la cápsula.
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !buscando,
                              child: AnimatedOpacity(
                                key: const Key('nav_busqueda_abierta'),
                                opacity: buscando ? 1 : 0,
                                duration: ms(250),
                                curve: curvaEase,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Row(
                                    children: [
                                      Icono(Ic.search, size: 24, color: p.mute),
                                      const SizedBox(width: 12),
                                      Expanded(child: widget.busqueda!),
                                      BotonCirculo(
                                        key: const Key('nav_cerrar_busqueda'),
                                        icono: Ic.x,
                                        etiqueta: 'Cerrar búsqueda (Esc)',
                                        tamanioIcono: 18,
                                        grosor: 2.4,
                                        onTap: widget.onCerrarBusqueda,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Desvanecer extends StatelessWidget {
  const _Desvanecer({required this.oculto, required this.child});
  final bool oculto;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: oculto,
        child: AnimatedOpacity(opacity: oculto ? 0 : 1, duration: ms(250), curve: curvaEase, child: child),
      );
}

/// `.nl.vbtn`: Venta, la píldora azul con el carrito.
class _BotonVenta extends StatelessWidget {
  const _BotonVenta({required this.etiqueta, required this.activa, required this.onTap, required this.onEnter});

  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        child: AlPasar(
          builder: (encima) => Tocable(
            key: const Key('nav_venta'),
            onTap: onTap,
            radio: 23,
            tooltip: 'Venta (Alt+1)',
            child: AnimatedContainer(
              duration: ms(200),
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(color: activa || encima ? p.azulOscuro : p.azul, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icono(Ic.cart, size: 20, color: Colors.white, grosor: 2.2),
                  const SizedBox(width: 8),
                  Text(etiqueta, style: estilo(16, 600, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.nl`: una sección como texto; al pasar o estar activa se tiñe de gris. Con mega-menú, el chevron gira al abrirse.
class _EnlaceNav extends StatelessWidget {
  const _EnlaceNav({
    required this.etiqueta,
    required this.activa,
    required this.conMega,
    required this.abierto,
    required this.onTap,
    required this.onEnter,
    this.onExit,
    this.onFoco,
  });

  final String etiqueta;
  final bool activa;
  final bool conMega;
  final bool abierto;
  final VoidCallback onTap;
  final VoidCallback onEnter;
  final VoidCallback? onExit;
  final VoidCallback? onFoco;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit?.call(),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) {
            if (f) onFoco?.call();
          },
          child: AlPasar(
            builder: (encima) {
              final resaltada = activa || encima || abierto;
              return Tocable(
                onTap: onTap,
                radio: 23,
                child: AnimatedContainer(
                  duration: ms(200),
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(color: resaltada ? p.s : p.s.withValues(alpha: 0), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: ms(200),
                        style: estilo(16, activa ? 600 : 500, color: resaltada ? p.tinta : p.mute),
                        child: Text(etiqueta, maxLines: 1),
                      ),
                      if (conMega) ...[
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: abierto ? .5 : 0,
                          duration: ms(250),
                          curve: curvaEase,
                          child: Opacity(opacity: .7, child: Icono(Ic.chevd, size: 14, color: resaltada ? p.tinta : p.mute, grosor: 2.6)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// `.aibtn`: "Asistente · Ctrl+K", píldora azul suave con la chispa. Compacto (ventanas angostas): solo la chispa.
class _BotonAsistente extends StatelessWidget {
  const _BotonAsistente({required this.onTap, required this.compacto});
  final VoidCallback onTap;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Levantable(
      builder: (context, encima) => Tocable(
        key: const Key('nav_asistente'),
        onTap: onTap,
        radio: 23,
        etiqueta: 'Asistente (Ctrl+K)',
        tooltip: 'Buscar o hacer algo · Ctrl+K',
        child: AnimatedContainer(
          duration: ms(200),
          height: 46,
          constraints: const BoxConstraints(minWidth: 46),
          padding: compacto ? const EdgeInsets.symmetric(horizontal: 14) : const EdgeInsets.fromLTRB(16, 0, 10, 0),
          decoration: BoxDecoration(
            color: encima ? Color.alphaBlend(p.azul.withValues(alpha: .18), p.azulClaro) : p.azulClaro,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icono(Ic.sparkle, size: 18, color: p.azul),
              if (!compacto) ...[
                const SizedBox(width: 9),
                Text('Asistente', style: estilo(15, 600, color: p.azul)),
                const SizedBox(width: 9),
                Kbd('Ctrl+K', color: p.azul, fondo: p.azul.withValues(alpha: .14), opacidad: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.mega`: el panel blanco a todo el ancho que baja desde atrás de la cápsula. Entra en 240 ms con `--quart` y sus filas
/// llegan escalonadas (25 ms cada una).
class _CapaMega extends StatelessWidget {
  const _CapaMega({required this.menu, required this.clave, required this.onEnter, required this.onExit, required this.onElegir});

  final MegaMenu? menu;
  final String? clave;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final abierto = menu != null;
    final ancho = MediaQuery.sizeOf(context).width;
    final lateral = ancho >= 1700 ? 120.0 : 64.0;
    return IgnorePointer(
      ignoring: !abierto,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: abierto ? 1 : 0),
        duration: hayMovimiento(context) ? ms(240) : Duration.zero,
        curve: curvaQuart,
        builder: (context, k, hijo) => Opacity(
          opacity: k.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, -14 * (1 - k)), child: k == 0 ? const SizedBox.shrink() : hijo),
        ),
        child: menu == null
            ? const SizedBox.shrink()
            : MouseRegion(
                onEnter: (_) => onEnter(),
                onExit: (_) => onExit(),
                child: Container(
                  key: Key('mega_$clave'),
                  padding: EdgeInsets.fromLTRB(lateral, 92, lateral, 40),
                  decoration: BoxDecoration(
                    color: p.papel,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(48)),
                    boxShadow: const [BoxShadow(color: Color(0x1F0D1017), blurRadius: 60, offset: Offset(0, 30))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(menu!.titulo, style: Tipos.h2(p.tinta, tamanio: 36).copyWith(height: 1.05)),
                              const SizedBox(height: 18),
                              Text(menu!.texto, style: estilo(16, 400, color: p.mute, alto: 1.5)),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 34),
                          decoration: BoxDecoration(border: Border(left: BorderSide(color: p.pelo))),
                          child: Column(
                            key: ValueKey(clave),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, it) in menu!.items.indexed) ...[
                                if (i > 0) const SizedBox(height: 4),
                                Aparecer(
                                  dy: 10,
                                  duracion: ms(400),
                                  curva: curvaQuart,
                                  demora: ms(i * 25 + 30),
                                  child: _FilaMega(item: it, onTap: () => onElegir(it.destino)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _FilaMega extends StatelessWidget {
  const _FilaMega({required this.item, required this.onTap});
  final ItemMegaMenu item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Transform.translate(
      offset: const Offset(-14, 0),
      child: AlPasar(
        builder: (encima) => Tocable(
          key: Key('mega_${item.destino}'),
          onTap: onTap,
          radio: 20,
          child: AnimatedContainer(
            duration: ms(200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: encima ? p.s : p.s.withValues(alpha: 0), borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Icono(item.icono, size: 22, color: p.mute, grosor: 1.9),
                const SizedBox(width: 14),
                Expanded(child: Text(item.titulo, style: estilo(18, 450, color: p.tinta))),
                if (item.pista != null) Text(item.pista!, style: estilo(13, 500, color: p.soft)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
