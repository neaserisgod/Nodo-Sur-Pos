// Nodo Sur Servicios con ventana de compu (Windows y navegador ancho), según el mock aprobado por el dueño el 2026-10-15
// (`docs/mock-servicios/NodoSurServicios-escritorio.html`, `docs/PLAN-ESCRITORIO-SERVICIOS.md`): la misma app del celular, con
// la barra inferior convertida en un menú lateral. Ninguna pantalla se escribe dos veces: con la ventana ancha cambia solo la
// disposición.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../servicios/marca_actual.dart';
import 'barra_inferior_ns.dart';
import 'iconos_ns.dart';
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

/// Desde este ancho la app de servicios se arma como en la compu: menú lateral y paneles. Debajo, la del celular.
const anchoEscritorioNs = 1000.0;

/// Ancho del menú lateral.
const anchoMenuLateralNs = 232.0;

/// Las pantallas pensadas para el celular no se estiran más que esto en la compu: renglones de un metro no se leen.
const anchoLecturaNs = 760.0;

/// Con la ventana ancha, el menú del negocio de servicios (Agenda, Cobrar…) está a la vista y usa todo el ancho. Mientras sea
/// true, `companion_app.dart` no achica la app al ancho de un celular; lo pone y lo saca `PantallaMenuCompanion`.
final ValueNotifier<bool> anchoLibreNs = ValueNotifier(false);

/// Se avisa cuando una pantalla entera tapa al menú (y cuando vuelve a quedar arriba). Solo páginas: las hojas y los diálogos
/// se abren encima del menú sin que cambie la disposición de atrás.
final RouteObserver<PageRoute<dynamic>> observadorRutasNs = RouteObserver<PageRoute<dynamic>>();

bool esAnchoEscritorioNs(BuildContext context) => MediaQuery.sizeOf(context).width >= anchoEscritorioNs;

/// Centra a [child] con un ancho cómodo de leer cuando la pantalla es más ancha que eso.
class AnchoLecturaNs extends StatelessWidget {
  const AnchoLecturaNs({super.key, required this.child, this.ancho = anchoLecturaNs});
  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child),
      );
}

/// Una entrada del menú lateral: la misma pestaña que la barra inferior del celular, con su atajo de teclado.
class EntradaMenuNs {
  const EntradaMenuNs({required this.pestania, required this.etiqueta, required this.icono, this.destacada = false});
  final PestaniaNs pestania;
  final String etiqueta;
  final IconoNs icono;

  /// Cobrar: el botón azul, como el del medio de la barra del celular.
  final bool destacada;
}

/// Las entradas de un negocio de servicios, en el orden del mock. Alt+1 es la primera, Alt+2 la segunda…
const entradasMenuServiciosNs = [
  EntradaMenuNs(pestania: PestaniaNs.inicio, etiqueta: 'Agenda', icono: IconoNs.calendario),
  EntradaMenuNs(pestania: PestaniaNs.vender, etiqueta: 'Cobrar', icono: IconoNs.billetes, destacada: true),
  EntradaMenuNs(pestania: PestaniaNs.productos, etiqueta: 'Servicios', icono: IconoNs.producto),
  EntradaMenuNs(pestania: PestaniaNs.caja, etiqueta: 'Caja', icono: IconoNs.billetera),
  EntradaMenuNs(pestania: PestaniaNs.mas, etiqueta: 'Más', icono: IconoNs.mas),
];

/// El menú lateral. [abajo] va pegado al pie (el estado del bot, por ejemplo).
class MenuLateralNs extends StatelessWidget {
  const MenuLateralNs({super.key, required this.activa, required this.onSeleccionar, this.hayActualizacion = false, this.abajo});

  final PestaniaNs activa;
  final ValueChanged<PestaniaNs> onSeleccionar;
  final bool hayActualizacion;
  final Widget? abajo;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Semantics(
      container: true,
      label: 'Secciones de la app',
      child: Container(
        width: anchoMenuLateralNs,
        decoration: BoxDecoration(color: ns.paper, border: Border(right: BorderSide(color: ns.s2))),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Negocio(),
            const SizedBox(height: 12),
            for (final (i, e) in entradasMenuServiciosNs.indexed) ...[
              if (e.destacada) const SizedBox(height: 6),
              _ItemMenu(
                entrada: e,
                atajo: 'Alt+${i + 1}',
                activa: activa == e.pestania,
                punto: e.pestania == PestaniaNs.mas && hayActualizacion,
                onTap: () => onSeleccionar(e.pestania),
              ),
              SizedBox(height: e.destacada ? 10 : 4),
            ],
            const Spacer(),
            ?abajo,
          ],
        ),
      ),
    );
  }
}

/// Atajos Alt+1… del menú lateral, para toda la ventana. Envuelve el contenido de la pantalla del menú.
class AtajosMenuNs extends StatelessWidget {
  const AtajosMenuNs({super.key, required this.onSeleccionar, required this.child, this.alEscape});
  final ValueChanged<PestaniaNs> onSeleccionar;
  final Widget child;

  /// Esc: cierra la pantalla abierta al lado del menú (en la compu no hay botón de volver del sistema).
  final VoidCallback? alEscape;

  static const _digitos = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          for (final (i, e) in entradasMenuServiciosNs.indexed)
            SingleActivator(_digitos[i], alt: true): () => onSeleccionar(e.pestania),
          const SingleActivator(LogicalKeyboardKey.escape): ?alEscape,
        },
        child: Focus(autofocus: true, child: child),
      );
}

class _Negocio extends StatelessWidget {
  const _Negocio();

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return ValueListenableBuilder(
      valueListenable: marcaActual,
      builder: (context, marca, _) {
        final nombre = marca.configurada && marca.nombre.isNotEmpty ? marca.nombre : 'Mi negocio';
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: TokensNs.ciruela, borderRadius: BorderRadius.circular(11)),
                child: Text(nombre.characters.first.toUpperCase(), style: estiloNs(15, peso: FontWeight.w700, color: TokensNs.ciruelaTexto)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w600, color: ns.ink)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.entrada, required this.atajo, required this.activa, required this.punto, required this.onTap});

  final EntradaMenuNs entrada;
  final String atajo;
  final bool activa;
  final bool punto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final destacada = entrada.destacada;
    final fondo = destacada ? TokensNs.marca : (activa ? ns.ibg : Colors.transparent);
    final color = destacada ? TokensNs.blanco : (activa ? ns.i : ns.mute);
    return Semantics(
      selected: activa,
      button: true,
      child: PresionNs(
        onTap: onTap,
        etiqueta: entrada.etiqueta,
        child: AnimatedContainer(
          duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 160),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(999),
            boxShadow: destacada && activa ? [BoxShadow(color: ns.ibg, spreadRadius: 3)] : null,
          ),
          child: Row(
            children: [
              IconoNsWidget(entrada.icono, tamanio: 20, color: color, grosor: 2.1),
              const SizedBox(width: 12),
              Expanded(child: Text(entrada.etiqueta, maxLines: 1, style: estiloNs(15, peso: FontWeight.w600, color: color))),
              if (punto)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(color: TokensNs.puntoActualizacion, shape: BoxShape.circle),
                ),
              Text(atajo, style: estiloNs(11, peso: FontWeight.w600, color: color.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marca el contenido que se ve al lado del menú lateral. Las pantallas de las pestañas lo preguntan para armarse a lo ancho
/// (la agenda con el turno al costado, Cobrar con el cobro a la derecha) y para no dejar lugar a una barra inferior que no está.
/// Una pantalla que se abre encima (otra ruta) no lo hereda: se ve como en el celular.
class ConMenuLateralNs extends InheritedWidget {
  const ConMenuLateralNs({super.key, required super.child});

  static bool de(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ConMenuLateralNs>() != null;

  @override
  bool updateShouldNotify(ConMenuLateralNs oldWidget) => false;
}

/// El ancho real de la ventana, aunque la app esté achicada al ancho de un celular (`companion_app.dart`).
double anchoDeLaVentanaNs(BuildContext context) {
  final vista = View.of(context);
  return vista.physicalSize.width / vista.devicePixelRatio;
}

/// El área de la derecha del menú lateral: las pestañas y, encima, lo que se abra desde ellas, en su propio navegador. Así una
/// pantalla secundaria (Configuración, Cuenta, el bot…) se ve al lado del menú, centrada a un ancho cómodo de leer, en vez de
/// tapar toda la ventana con el ancho de un celular.
class ContenidoConMenuNs extends StatelessWidget {
  const ContenidoConMenuNs({super.key, required this.navegador, required this.pestanias});

  final GlobalKey<NavigatorState> navegador;
  final Widget pestanias;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return _PestaniasActuales(
      pestanias: pestanias,
      child: Theme(
        data: tema.copyWith(
          pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const _TransicionAlLadoDelMenu()}),
        ),
        child: Navigator(
          key: navegador,
          onGenerateInitialRoutes: (_, _) => [
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              // Un widget propio que lee las pestañas: la ruta guarda la página armada y no la vuelve a pedir.
              pageBuilder: (_, _, _) => const _PaginaPestanias(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las pestañas que arma el menú en cada redibujo: la ruta de abajo del navegador las lee de acá (una ruta no se vuelve a armar
/// sola cuando cambia quien la creó).
class _PestaniasActuales extends InheritedWidget {
  const _PestaniasActuales({required this.pestanias, required super.child});
  final Widget pestanias;

  static Widget de(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_PestaniasActuales>()!.pestanias;

  @override
  bool updateShouldNotify(_PestaniasActuales oldWidget) => !identical(pestanias, oldWidget.pestanias);
}

/// Las pantallas que se abren al lado del menú: con el fundido de la app y centradas a [anchoLecturaNs] (están pensadas para el
/// celular: estiradas a todo el ancho quedaban renglones de un metro).
class _TransicionAlLadoDelMenu extends PageTransitionsBuilder {
  const _TransicionAlLadoDelMenu();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final contenido = route.isFirst ? child : ColoredBox(color: context.ns.paper, child: AnchoLecturaNs(child: child));
    if (sinMovimiento(context)) return contenido;
    return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: contenido);
  }
}

class _PaginaPestanias extends StatelessWidget {
  const _PaginaPestanias();

  @override
  Widget build(BuildContext context) => ConMenuLateralNs(child: _PestaniasActuales.de(context));
}

/// Está armado el menú (ya se entró). Mientras no, la compu muestra la bienvenida y el entrar con [PanelMarcaEscritorioNs] al
/// costado; lo pone y lo saca `PantallaMenuCompanion`.
final ValueNotifier<bool> menuMontadoNs = ValueNotifier(false);

/// La mitad izquierda de la bienvenida y del entrar en la compu (El dueño, 2026-10-15: "la bienvenida y entrar se ven de
/// celular"): el color y la palabra del ícono, y qué es la app. El formulario va a la derecha, del ancho de siempre.
class PanelMarcaEscritorioNs extends StatelessWidget {
  const PanelMarcaEscritorioNs({super.key});

  static const _puntos = [
    'La agenda, los cobros y la caja, los mismos que en el celular.',
    'El bot de WhatsApp contesta y cobra señas aunque cierres la app.',
    'Todo se sincroniza solo con tus otros equipos.',
  ];

  @override
  Widget build(BuildContext context) {
    // Material (no ColoredBox): va arriba del navegador, fuera de toda pantalla, y sin él el texto sale con el subrayado amarillo
    // de "falta el tema".
    return Material(
      color: TokensNs.ciruela,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 56, 56, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('turnos', style: estiloNs(30, peso: FontWeight.w600, track: -0.03, color: TokensNs.ciruelaTexto)),
                const SizedBox(width: 6),
                Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 14), decoration: const BoxDecoration(color: TokensNs.ciruelaTexto, shape: BoxShape.circle)),
              ],
            ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nodo Sur Servicios', style: estiloNs(16, peso: FontWeight.w600, color: TokensNs.ciruelaTexto.withValues(alpha: 0.75))),
                  const SizedBox(height: 10),
                  Text('Tus turnos, tus señas y tu WhatsApp, desde la compu.',
                      style: tituloNs(44, track: -0.05, altura: 1.05, color: TokensNs.ciruelaTexto)),
                  const SizedBox(height: 28),
                  for (final p in _puntos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(padding: const EdgeInsets.only(top: 2), child: IconoNsWidget(IconoNs.tilde, tamanio: 20, color: TokensNs.ciruelaTexto)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(p, style: estiloNs(16, altura: 1.4, color: TokensNs.ciruelaTexto))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Text('horsepos.com', style: estiloNs(14, color: TokensNs.ciruelaTexto.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}
