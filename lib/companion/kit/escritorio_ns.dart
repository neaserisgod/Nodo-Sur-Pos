// Nodo Sur Servicios con ventana de compu (Windows y navegador ancho), según el mock aprobado por el dueño el 2026-10-15
// (`docs/mock-servicios/NodoSurServicios-escritorio.html`, `docs/PLAN-ESCRITORIO-SERVICIOS.md`): la misma app del celular, con
// la barra inferior convertida en un menú lateral. Ninguna pantalla se escribe dos veces: con la ventana ancha cambia solo la
// disposición.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../edicion.dart' show esEdicionGastronomia;
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

/// Las de un local gastronómico (§22): abre en los Pedidos y la carta reemplaza a los servicios, como en la barra del celular.
const entradasMenuGastronomiaNs = [
  EntradaMenuNs(pestania: PestaniaNs.inicio, etiqueta: 'Pedidos', icono: IconoNs.portapapeles),
  EntradaMenuNs(pestania: PestaniaNs.vender, etiqueta: 'Vender', icono: IconoNs.carrito, destacada: true),
  EntradaMenuNs(pestania: PestaniaNs.productos, etiqueta: 'Carta', icono: IconoNs.producto),
  EntradaMenuNs(pestania: PestaniaNs.caja, etiqueta: 'Caja', icono: IconoNs.billetera),
  EntradaMenuNs(pestania: PestaniaNs.mas, etiqueta: 'Más', icono: IconoNs.mas),
];

/// Las entradas del menú lateral de esta edición.
List<EntradaMenuNs> get entradasMenuNs => esEdicionGastronomia ? entradasMenuGastronomiaNs : entradasMenuServiciosNs;

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
            for (final (i, e) in entradasMenuNs.indexed) ...[
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
  const AtajosMenuNs({super.key, required this.onSeleccionar, required this.child});
  final ValueChanged<PestaniaNs> onSeleccionar;
  final Widget child;

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
          for (final (i, e) in entradasMenuNs.indexed)
            SingleActivator(_digitos[i], alt: true): () => onSeleccionar(e.pestania),
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
