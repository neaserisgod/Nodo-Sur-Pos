// La barra de búsqueda y todo lo que cuelga de ella o vive cerca — hasta el
// rediseño de composición 2026-09-25 esto era una columna angosta a la
// izquierda de la pantalla, con el campo arriba y una `Superficie` debajo
// que alternaba entre resultados y accesos directos. El dueño la rechazó dos
// veces seguidas: primero la distribución en general, después puntual
// ("los productos deben salir de la barra de busqueda, no de la izquierda")
// — la columna entera se borró.
//
// Ahora es una sola pieza: `BarraBusquedaVenta`, el campo de ancho fijo con
// sus resultados colgando de ÉL MISMO como un dropdown flotante
// (Google/Gmail), anclado con
// `CompositedTransformTarget`/`CompositedTransformFollower` — no una
// columna fija en la pantalla. La tira de accesos directos por Alt+tecla
// que vivía acá al lado (cigarrillos, "Varios", "Vuelto") se sacó entera
// (El dueño, cuarta pasada: "ahora no hacen falta los accesos rapidos...
// sacar la tira Y el sistema de accesos directos entero" — la grilla
// táctil de `RejillaProductos`, más abajo en este mismo archivo, cubre el
// acceso rápido). "Varios" sigue andando por Alt+V o escribiéndolo en la
// búsqueda; "Vuelto" por Alt+C o apareciendo como cualquier otro producto
// en la grilla.
//
// El campo único sigue siendo la entrada principal para escribir/escanear
// (autofocus al arrancar), pero el foco YA NO se fuerza de vuelta después
// de cualquier acción (El dueño, 2026-09-16: "dejar de robar el foco al hacer
// otra cosa") — agregar por tap/Alt+tecla y cobrar siguen devolviendo el
// foco (son el flujo normal de seguir vendiendo), pero abrir un diálogo
// secundario (Mixto, Varios) ya no lo hace: el foco se queda donde haya
// quedado al cerrarse, en vez de saltar solo.
//
// Alta rápida (dar de alta un producto nuevo sin salir de esta pantalla) se
// sacó de acá (El dueño, 2026-09-16): un código/nombre sin coincidencias
// muestra el aviso y nada más — cargar un producto nuevo pasa a ser
// siempre desde Proveedores. `dialogo_alta_rapida.dart` se borró (ya no
// tiene ningún llamador).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/pesables.dart';
import '../../domain/venta.dart';
import '../comun/color_categoria.dart';
import '../tema/tokens.dart';
import 'acciones_venta.dart';
import 'tacto_venta.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/movimiento.dart';
import '../tema/acentos.dart';

/// Alto máximo del dropdown de resultados antes de scrollear — "6 a 8
/// filas" (CLAUDE.md, especificación original de esta pantalla), sin
/// depender de cuántas coincidencias haya: con pocas, el dropdown se achica
/// solo (`shrinkWrap: true` en el `ListView` de más abajo); con muchas, se
/// tapa acá y scrollea.
const double _altoMaximoDropdown = 420;

/// Función compartida por la barra de búsqueda (Enter con texto/vacío) y
/// cualquier otro lugar que necesite el mismo camino — separada de
/// `BarraBusquedaVenta` para que no dependa de ser un método de widget.
Future<void> _onEnterBusqueda(BuildContext context) async {
  final c = context.read<VentaControlador>();
  if (c.hayTexto) {
    if (c.coincidencias.isEmpty) {
      // Sin coincidencias, o el texto es un producto conocido sin stock
      // (`productoSinStockEncontrado`): nada que agregar — el aviso ya
      // está en el dropdown, Enter no hace nada más.
    } else if (c.coincidencias[c.indicePreseleccionado].esVarios) {
      // "Varios" no se excluye de la búsqueda (si alguien escribió
      // "varios" lo quiere a propósito), pero necesita el mismo diálogo
      // de monto que Alt+V — agregarlo directo no tiene precio que poner.
      // El foco NO vuelve solo al cerrarse este diálogo (El dueño,
      // 2026-09-16): es un paso secundario, no el flujo de escanear.
      await agregarVarios(context, c);
      return;
    } else {
      c.agregarSeleccionActual();
    }
  } else {
    // Campo vacío: cobra la venta, igual que el botón "Cobrar". Si el
    // medio es mixto y todavía no se confirmó el monto en efectivo,
    // cobrarActual() simplemente no hace nada — no hay nada raro que
    // manejar acá. Mismo camino que el botón: si el canal elegido es de
    // la terminal Point (fase 12), pasa por el diálogo de cobro en vez
    // de grabar directo.
    await cobrarOAbrirPosnet(context, c);
  }
  // Agregar por Enter y cobrar sí devuelven el foco — es la continuación
  // natural de escanear/vender, a diferencia de un diálogo secundario
  // (arriba).
  c.focoCampoPrincipal.requestFocus();
}

/// El campo único, de ancho fijo ("estilo Google", el dueño, rediseño
/// 2026-09-25), con sus propios resultados colgando de él como un dropdown
/// flotante — no de una columna fija en la pantalla ("los productos deben
/// salir de la barra de busqueda, no de la izquierda"). `Stateful` para
/// sostener el `LayerLink` (ancla el dropdown al campo) y el
/// `OverlayPortalController` — mismo mecanismo estándar de Flutter que
/// cualquier autocomplete anclado a un campo de texto.
///
/// [anchoDropdown] es el ancho YA resuelto por el `LayoutBuilder` de
/// `pantalla_venta.dart` (el mismo que se le da a este campo): el dropdown
/// tiene que calzar exacto con el campo, nunca un ancho propio inventado.
class BarraBusquedaVenta extends StatefulWidget {
  const BarraBusquedaVenta({super.key, required this.anchoDropdown});

  final double anchoDropdown;

  @override
  State<BarraBusquedaVenta> createState() => _BarraBusquedaVentaState();
}

class _BarraBusquedaVentaState extends State<BarraBusquedaVenta> {
  final _link = LayerLink();
  final _overlayController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // El portal queda "mostrado" una sola vez acá — el builder de abajo es
    // el que decide, en cada rebuild, si pinta algo o `SizedBox.shrink()`
    // según el estado del controlador. Llamar a `show()`/`hide()` recién
    // ahí (en vez de acá) dispararía un `setState` en medio de la
    // construcción del árbol.
    _overlayController.show();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final colores = context.colores;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        // El aviso (Regla 7: pesable sin gramos o sin precio por kilo)
        // puede dispararse SIN texto escrito — se agrega también desde un
        // acceso directo (`TiraAccesosDirectos`), no solo desde acá. Por
        // eso el dropdown se muestra con aviso solo, sin lista, en ese
        // caso — nunca se pierde el mensaje por no estar escribiendo.
        final mostrar = c.hayTexto || c.avisoBusqueda != null;
        if (!mostrar) return const SizedBox.shrink();

        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, Espaciado.sm),
          // `UnconstrainedBox`: el `Overlay` le pasa a este hijo una
          // constraint mucho más grande que su contenido real (bug real,
          // visto en `capturas/venta-claro.png` — un scrim gris/opaco
          // tapaba todo lo de abajo, invisible en oscuro solo porque se
          // fundía con el fondo). Sin esto, `Superficie` se estiraba a esa
          // constraint en vez de medirse por su contenido.
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            // Cae unos px desde el campo al abrirse (2026-10-03); escribir no la vuelve a animar (es el mismo widget).
            child: Entrada(
              desplazamiento: -6,
              child: SizedBox(
              width: widget.anchoDropdown,
              child: Container(
                // Key propia: desde que la grilla de productos muestra permanentemente el mismo nombre que puede aparecer acá
                // (`RejillaProductos`), los tests necesitan poder acotar un `find.text` a "adentro del dropdown".
                key: const Key('dropdown_resultados_busqueda'),
                // Como el mock (`.drop`): hoja blanca de radio 36, borde finito y una sombra grande y suave; opaca, porque flota
                // encima del carrito y de la grilla.
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colores.fondo,
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: colores.textoPrimario.withValues(alpha: 0.07)),
                  boxShadow: [BoxShadow(color: const Color(0xFF0D1017).withValues(alpha: 0.22), blurRadius: 80, offset: const Offset(0, 30))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.avisoBusqueda != null) ...[
                      Text(c.avisoBusqueda!, style: TextStyle(color: colores.error)),
                      if (c.hayTexto) const SizedBox(height: Espaciado.sm),
                    ],
                    if (c.hayTexto) const _ResultadosBusqueda(),
                  ],
                ),
              ),
            ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: _CampoUnico(controlador: c),
      ),
    );
  }
}

/// El campo único como el mock (`.sbig`): pastilla gris de 72 px, texto de 22 px, lupa a la izquierda; al enfocarlo pasa a fondo blanco
/// con un aro azul de 3 px. Se dibuja a mano (no con el borde de `InputDecoration`) para que el aro no mueva nada al aparecer.
class _CampoUnico extends StatefulWidget {
  const _CampoUnico({required this.controlador});

  final VentaControlador controlador;

  @override
  State<_CampoUnico> createState() => _CampoUnicoState();
}

class _CampoUnicoState extends State<_CampoUnico> {
  @override
  void initState() {
    super.initState();
    widget.controlador.focoCampoPrincipal.addListener(_cambioFoco);
  }

  @override
  void dispose() {
    widget.controlador.focoCampoPrincipal.removeListener(_cambioFoco);
    super.dispose();
  }

  void _cambioFoco() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    final colores = context.colores;
    final enfocado = c.focoCampoPrincipal.hasFocus;
    return AnimatedContainer(
      duration: Animaciones.corta,
      curve: Animaciones.curva,
      decoration: BoxDecoration(
        color: enfocado ? colores.fondo : colores.fondoBloque,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: enfocado ? focoMock : Colors.transparent, spreadRadius: 3)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        children: [
          IconoPlz(IconosPlazoleta.search, size: 26, color: colores.textoPrimario),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: c.campoTexto,
              focusNode: c.focoCampoPrincipal,
              autofocus: true,
              cursorColor: colores.textoPrimario,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: Pesos.regular, letterSpacing: -0.44),
              decoration: InputDecoration(
                hintText: 'Escaneá un código o buscá un producto',
                hintStyle: TextStyle(fontSize: 22, fontWeight: Pesos.regular, color: colores.textoTenue, letterSpacing: -0.44),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isCollapsed: true,
              ),
              onSubmitted: (_) => _onEnterBusqueda(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que cuelga del campo mientras hay texto escrito: mismas tres ramas
/// que antes resolvía `_AreaUnificada` — "Sin coincidencias", una
/// coincidencia sin stock, o la lista con tope de alto. Los accesos
/// directos NO viven acá (ver `TiraAccesosDirectos`, aparte) — este widget
/// asume que ya hay texto, lo garantiza el llamador (`BarraBusquedaVenta`).
class _ResultadosBusqueda extends StatelessWidget {
  const _ResultadosBusqueda();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();

    if (c.sinCoincidencias) {
      // Sin alta rápida (El dueño, 2026-09-16): un aviso plano, sin acción —
      // dar de alta un producto nuevo pasa a ser siempre desde Proveedores.
      return Align(
        alignment: Alignment.topLeft,
        child: Text('Sin coincidencias', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    // Existe pero sin stock (El dueño, 2026-09-06: "si no hay stock, no
    // aparece en ventas") — sin InkWell ni acción: no es ni un resultado
    // para agregar ni un candidato para dar de alta, ofrecer cualquiera de
    // las dos cosas sería un error (ya existe, no es nuevo).
    if (c.productoSinStockEncontrado case final producto?) {
      return Align(
        alignment: Alignment.topLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(producto.nombre, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              'Sin stock — no se puede vender',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colores.error),
            ),
          ],
        ),
      );
    }

    // Gramos ya escritos en el campo ("200 queso"), si los hay — misma
    // interpretación que usa el controlador para agregar la línea, para que
    // la fila muestre exactamente lo que va a pasar al tocarla o al Enter.
    final gramos = interpretarTexto(c.campoTexto.text).gramos;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _altoMaximoDropdown),
      child: ListView.separated(
        // `shrinkWrap`: pocas coincidencias no dejan un hueco vacío hasta
        // el tope de `_altoMaximoDropdown` — el dropdown se achica con el
        // contenido, como cualquier autocomplete real.
        shrinkWrap: true,
        itemCount: c.coincidencias.length,
        separatorBuilder: (context, index) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final producto = c.coincidencias[index];
          final seleccionado = index == c.indicePreseleccionado;
          return _FilaResultado(
            producto: producto,
            gramos: gramos,
            seleccionado: seleccionado,
            onTap: () async {
              final ctrl = context.read<VentaControlador>();
              if (producto.esVarios) {
                await agregarVarios(context, ctrl);
              } else {
                ctrl.agregarDesdeBusqueda(producto);
                ctrl.focoCampoPrincipal.requestFocus();
              }
            },
          );
        },
      ),
    );
  }
}

/// Un resultado de búsqueda como fila de una línea (El dueño, corrección
/// post-revisión: las cards de dos líneas se leían en diagonal y ocupaban
/// 96px para solo dos datos). Tres datos, siempre en el mismo orden:
/// nombre · stock · precio — mismo criterio de alineación que cualquier
/// otra lista de la app (`DISENO.md`, "Reglas de alineación"). El nombre se
/// trunca con `ellipsis` si no entra (vuelta atrás deliberada: la fila
/// gana altura cómoda, pero es de una sola línea, no dos).
///
/// El teclado sigue mandando (requisito que no se negocia): esto es una
/// superficie más grande para tocar con el mouse, nunca algo que haga
/// falta usar — las flechas y Enter siguen agregando sin que el foco se
/// mueva del campo único.
///
/// Sin marcar stock bajo en rojo acá (corrección post-revisión: "un
/// producto sin stock se marca en un solo lugar, no en los dos" — ese lugar
/// es el carrito, `columna_carrito.dart`, que es donde CLAUDE.md lo pide
/// desde el principio; el aviso duplicado acá era una adición de más).
class _FilaResultado extends StatelessWidget {
  const _FilaResultado({
    required this.producto,
    required this.gramos,
    required this.seleccionado,
    required this.onTap,
  });

  final Producto producto;
  final int? gramos;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {

    final String stockTexto;
    final String precioTexto;
    // El precio por kilo (sin gramos escritos todavía) es una TARIFA de
    // referencia, no el monto a pagar — se distingue con un tamaño menor;
    // el subtotal real (gramos ya escritos, o cualquier producto por
    // unidad) usa el tamaño grande de siempre.
    final bool precioEsTarifa;

    if (producto.esVarios) {
      // "Varios" no tiene precio fijo ni stock en el sentido de Regla 8 —
      // mostrar vacío se leía como un error (corrección post-revisión); un
      // guion deja claro que no aplica, no que falta un dato.
      stockTexto = '—';
      precioTexto = '—';
      precioEsTarifa = true;
    } else if (producto.esPesable) {
      stockTexto = '${producto.stockGramos ?? 0} g';
      final precioPorKilo = producto.precioPorKiloCentavos;
      if (gramos != null) {
        precioTexto = precioPorKilo == null
            ? '—'
            : formatearARS(
                subtotalPesable(
                  montoPorKiloCentavos: precioPorKilo,
                  gramos: gramos!,
                ),
              );
        precioEsTarifa = false;
      } else {
        // Nunca partido en dos widgets (bug real, ver TRAMPAS.md): "/kg" es
        // parte del mismo texto que el monto, no una etiqueta aparte.
        precioTexto = precioPorKilo == null
            ? '—'
            : '${formatearARS(precioPorKilo)}/kg';
        precioEsTarifa = true;
      }
    } else {
      stockTexto = '${producto.stock} un.';
      precioTexto = producto.precioCentavos == null
          ? '—'
          : formatearARS(producto.precioCentavos!);
      precioEsTarifa = false;
    }

    // Agotado: atenuado y con "Sin stock" en vez de la cantidad (El dueño, 2026-10-03).
    final agotado = !tieneStock(producto);
    final fondo = context.colores.fondoBloque;
    return Opacity(
      opacity: agotado ? 0.5 : 1,
      child: SuperficieTactil(
        color: seleccionado ? fondo : Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            children: [
              AvatarProducto(producto: producto, tamano: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  producto.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 21, fontWeight: Pesos.regular),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Text(
                agotado ? 'Sin stock' : stockTexto,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario, fontSize: 15).tabular,
              ),
              SizedBox(
                width: 130,
                child: Text(
                  precioTexto,
                  textAlign: TextAlign.right,
                  style: (precioEsTarifa
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario, fontSize: 15)
                          : Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 21, fontWeight: Pesos.fuerte))!
                      .tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El círculo con la inicial del producto, teñido con el color de su rubro (`.av` del mock). Sin categoría, gris.
class AvatarProducto extends StatelessWidget {
  const AvatarProducto({super.key, required this.producto, this.tamano = 44});

  final Producto producto;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final color = colorCategoria(context, producto.categoriaId) ?? colores.textoSecundario;
    final inicial = producto.nombre.trim().isEmpty ? '?' : producto.nombre.trim().characters.first.toUpperCase();
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.16), colores.fondo), shape: BoxShape.circle),
      child: Text(inicial, style: TextStyle(fontSize: tamano * 0.39, fontWeight: Pesos.fuerte, color: color)),
    );
  }
}

/// Categoría "sin categoría cargada" en la grilla — un `Object` propio en
/// vez de un sentinel numérico (`-1` chocaría, en teoría, con un id real):
/// identidad, no valor, así que no hay forma de confundirlo con un
/// `categoriaId` de verdad.
final Object _sinCategoriaEnGrilla = Object();

/// La pill "Todos" (tercera pasada: antes era el default implícito de
/// `_filtro == null`; ahora ese lugar lo ocupa "Más vendidos" y "Todos"
/// necesita su propia identidad explícita para poder elegirse).
final Object _todosEnGrilla = Object();

/// Grilla de productos navegable por categoría (rediseño 2026-09-25,
/// segunda pasada: El dueño mandó una referencia de POS con esto y contestó
/// "1 pero manteniendo la estructura de dropdown" — se suma como una forma
/// MÁS de agregar, tocando en vez de escribir/escanear; no reemplaza nada
/// de eso). Qué categoría está elegida es estado de UI puro (no afecta el
/// carrito ni ningún atajo) — `Stateful` local, sin pasar por
/// `VentaControlador` (CLAUDE.md: "sin gestor de estado ceremonioso").
class RejillaProductos extends StatefulWidget {
  const RejillaProductos({super.key, this.altoTarjeta = 150});

  /// Alto de cada tarjeta (150 en el mock; menos en ventanas de poca altura).
  final double altoTarjeta;

  @override
  State<RejillaProductos> createState() => _RejillaProductosState();
}

class _RejillaProductosState extends State<RejillaProductos> {
  /// `null` = sin elegir explícito todavía → "Más vendidos" (o "Todos" si
  /// no hay historial de ventas, para no arrancar con una grilla vacía en
  /// una instalación nueva). `_todosEnGrilla`/`_sinCategoriaEnGrilla` = esas
  /// pills. Un `int` = esa categoría.
  Object? _filtro;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final catalogo = c.catalogoVisible;

    // Solo pills con al menos un producto detrás — una que lleve a una
    // grilla vacía es peor que no mostrarla.
    final idsConProductos = catalogo.map((p) => p.categoriaId).toSet();
    final categoriasConProductos = c.categorias
        .where((cat) => idsConProductos.contains(cat.id))
        .toList();
    final hayNoCategorizados = idsConProductos.contains(null);

    final porId = {for (final p in catalogo) p.id: p};
    final masVendidos = [for (final id in c.idsMasVendidos) ?porId[id]];

    final List<Producto> productos;
    if (_filtro == null) {
      productos = masVendidos.isNotEmpty ? masVendidos : catalogo;
    } else if (identical(_filtro, _todosEnGrilla)) {
      productos = catalogo;
    } else if (identical(_filtro, _sinCategoriaEnGrilla)) {
      productos = catalogo.where((p) => p.categoriaId == null).toList();
    } else {
      productos = catalogo.where((p) => p.categoriaId == _filtro).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PildoraCategoria(
                        texto: 'Más vendidos',
                        seleccionada: _filtro == null,
                        onTap: () => setState(() => _filtro = null),
                      ),
                      const SizedBox(width: 8),
                      _PildoraCategoria(
                        texto: 'Todos',
                        seleccionada: identical(_filtro, _todosEnGrilla),
                        onTap: () => setState(() => _filtro = _todosEnGrilla),
                      ),
                      for (final cat in categoriasConProductos) ...[
                        const SizedBox(width: 8),
                        _PildoraCategoria(
                          texto: cat.nombre,
                          seleccionada: _filtro == cat.id,
                          onTap: () => setState(() => _filtro = cat.id),
                        ),
                      ],
                      if (hayNoCategorizados) ...[
                        const SizedBox(width: 8),
                        _PildoraCategoria(
                          texto: 'Otros',
                          seleccionada: identical(_filtro, _sinCategoriaEnGrilla),
                          onTap: () => setState(() => _filtro = _sinCategoriaEnGrilla),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // "Varios" a la vista (rediseño v4): un monto suelto para lo que no está cargado. Antes solo por Alt+V.
              const _PildoraVarios(),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: productos.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    _filtro == null ? 'Todavía no hay historial de ventas.' : 'Sin productos en esta categoría',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, r) {
                    // Cinco columnas a 1920 px (como el mock); menos cuando la ventana es más angosta.
                    final columnas = ((r.maxWidth + 14) / 214).floor().clamp(2, 6);
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 14),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnas,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: widget.altoTarjeta,
                      ),
                      itemCount: productos.length,
                      itemBuilder: (context, index) => entradaEnLista(index, _TarjetaProducto(producto: productos[index])),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// "Varios · Alt+V" al final de la fila de categorías: no filtra nada, abre el diálogo de monto suelto.
class _PildoraVarios extends StatelessWidget {
  const _PildoraVarios();

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final c = context.read<VentaControlador>();
    return Container(
      key: const Key('pildora_varios'),
      height: 46,
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colores.textoPrimario.withValues(alpha: 0.12)),
      ),
      child: SuperficieTactil(
        borderRadius: BorderRadius.circular(999),
        onTap: () => agregarVarios(context, c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Varios', style: TextStyle(color: colores.textoSecundario, fontSize: 16, fontWeight: Pesos.intermedio)),
              const SizedBox(width: 8),
              TeclaAtajo(texto: 'Alt+V', color: colores.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

/// El atajo impreso en un botón (`.kbd` del mock): letra chica en una cápsula apenas teñida.
class TeclaAtajo extends StatelessWidget {
  const TeclaAtajo({super.key, required this.texto, required this.color, this.tamano = 12});

  final String texto;
  final Color color;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(8)),
      child: Text(
        texto,
        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: tamano, fontWeight: Pesos.medium, letterSpacing: 0.24, height: 1.3),
      ),
    );
  }
}

/// "Pagar proveedor · Alt+P": pastilla oscura al lado del buscador (la acción principal de caja además de vender).
class BotonPagarProveedor extends StatelessWidget {
  const BotonPagarProveedor({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Tooltip(
      message: 'Pagar proveedor (Alt+P)',
      child: Container(
        key: const Key('boton_pagar_proveedor'),
        decoration: BoxDecoration(color: colores.textoPrimario, borderRadius: BorderRadius.circular(999)),
        child: SuperficieTactil(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconoPlz(IconosPlazoleta.localShippingOutlined, size: 22, color: colores.fondo),
                const SizedBox(width: 10),
                Text('Pagar proveedor', style: TextStyle(color: colores.fondo, fontSize: 17, fontWeight: Pesos.medium)),
                const SizedBox(width: 10),
                TeclaAtajo(texto: 'Alt+P', color: colores.fondo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill de filtro (`.chip` del mock): blanca con un borde finito; la elegida, de tinta con letra blanca.
class _PildoraCategoria extends StatelessWidget {
  const _PildoraCategoria({required this.texto, required this.seleccionada, required this.onTap});

  final String texto;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return AnimatedContainer(
      duration: Animaciones.corta,
      curve: Animaciones.curva,
      height: 46,
      decoration: BoxDecoration(
        color: seleccionada ? colores.textoPrimario : colores.fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: seleccionada ? Colors.transparent : colores.textoPrimario.withValues(alpha: 0.12)),
      ),
      child: SuperficieTactil(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Center(
            child: Text(
              texto,
              style: TextStyle(
                color: seleccionada ? colores.fondo : colores.textoPrimario,
                fontSize: 16,
                fontWeight: Pesos.intermedio,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de la grilla (`.tile` del mock): gris, radio 30, con la inicial de color arriba a la izquierda, el nombre y el precio abajo;
/// con el producto en el carrito se tiñe de azul claro, lleva aro azul y un contador arriba a la derecha.
class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final c = context.watch<VentaControlador>();
    final enCarrito = c.carrito.where((l) => l.productoId == '${producto.id}').firstOrNull;
    final agotado = !tieneStock(producto);

    final String precioTexto;
    if (producto.esPesable) {
      final precioPorKilo = producto.precioPorKiloCentavos;
      precioTexto = precioPorKilo == null ? '—' : formatearARS(precioPorKilo);
    } else {
      precioTexto = producto.precioCentavos == null ? '—' : formatearARS(producto.precioCentavos!);
    }
    final minimo = producto.esPesable ? producto.stockMinimoGramos : producto.stockMinimo;
    final stock = producto.esPesable ? (producto.stockGramos ?? 0) : producto.stock;
    final pocoStock = !agotado && minimo != null && minimo > 0 && stock < minimo;

    final cantidad = switch (enCarrito) {
      LineaVentaPorUnidad u => '${u.cantidad}',
      LineaVentaPesable p => '${p.gramos} g',
      _ => null,
    };
    final azulClaro = context.azulSuaveFondo;

    return Opacity(
      opacity: agotado ? 0.45 : 1,
      child: AnimatedContainer(
        duration: Animaciones.media,
        curve: Animaciones.curva,
        decoration: BoxDecoration(
          color: enCarrito != null ? azulClaro : colores.fondoBloque,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: enCarrito != null ? azulMarca : Colors.transparent, width: 2),
        ),
        child: SuperficieTactil(
          borderRadius: BorderRadius.circular(30),
          onTap: agotado
              ? null
              : () {
                  final ctrl = context.read<VentaControlador>();
                  ctrl.agregarProducto(producto);
                  ctrl.focoCampoPrincipal.requestFocus();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AvatarProducto(producto: producto),
                    const Spacer(),
                    Text(
                      producto.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: Pesos.intermedio, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            precioTexto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 25, fontWeight: Pesos.intermedio, letterSpacing: -0.9).tabular,
                          ),
                        ),
                        if (producto.esPesable) ...[
                          const SizedBox(width: 6),
                          Text('/kg', style: TextStyle(fontSize: 14, fontWeight: Pesos.medium, color: colores.textoSecundario)),
                        ],
                        if (agotado || pocoStock) ...[
                          const SizedBox(width: 8),
                          _EtiquetaStock(texto: agotado ? 'Sin stock' : 'Quedan ${producto.esPesable ? '${(stock / 1000).toStringAsFixed(1).replaceAll('.', ',')} kg' : stock}', error: agotado),
                        ],
                      ],
                    ),
                  ],
                ),
                if (cantidad != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _ContadorEnTarjeta(texto: cantidad),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Quedan 14" / "Sin stock" junto al precio (`.tile .p small`).
class _EtiquetaStock extends StatelessWidget {
  const _EtiquetaStock({required this.texto, required this.error});

  final String texto;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final fondo = error ? Color.alphaBlend(context.colores.error.withValues(alpha: 0.14), context.colores.fondo) : acentos.alertaSuave;
    final letra = error ? context.colores.error : acentos.alerta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: TextStyle(fontSize: 13, fontWeight: Pesos.medium, color: letra)),
    );
  }
}

/// El número azul de arriba a la derecha de una tarjeta con el producto en el carrito (`.tile .cnt`): late cuando cambia.
class _ContadorEnTarjeta extends StatelessWidget {
  const _ContadorEnTarjeta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Pulso(
      valor: texto,
      escala: 1.18,
      child: Container(
        constraints: const BoxConstraints(minWidth: 30),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: azulMarca, borderRadius: BorderRadius.circular(15)),
        child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
