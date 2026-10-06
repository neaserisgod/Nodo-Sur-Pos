// La pantalla de Venta del mock v4 (`.venta`, `SCR.venta` en `p4_venta.js`), hecha desde cero (2026-10-06, el dueño:
// "fidelidad visual 1:1 con el mock"). Dos zonas:
//
//  * Izquierda: el campo único grande (72 px) con "Pagar proveedor · Alt+P" al lado y el desplegable de resultados
//    colgando de los dos; debajo las categorías como chips (con "Varios · Alt+V" al final) y la grilla de tarjetas.
//  * Derecha: el panel gris de radio 52 con las pestañas de ventas abiertas, el carrito (scrollea), el total oscuro, los
//    cuatro medios de pago en 2×2 y "Cobrar".
//
// Regla dura (CLAUDE.md): búsqueda, total y medios de pago siempre a la vista sin scrollear; el carrito es lo único que
// scrollea. Con poca altura (1366×768) se achican el campo, las tarjetas, el total, los medios y Cobrar: nunca se
// esconden.
//
// Todo lee de `VentaControlador` (no hay lógica de negocio acá): agregar, quitar, cantidades, medios, cobrar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../domain/cobro_posnet.dart' show canalCredito, canalDebito, canalQr, esCanalTarjeta;
import '../../domain/medio_pago.dart';
import '../../domain/pesables.dart';
import '../../domain/venta.dart';
import '../comun/aviso_superior.dart';
import '../kit/kit.dart';
import 'acciones_venta.dart';
import 'cancelar_venta_con_deshacer.dart';
import 'dialogo_descuento.dart';
import 'dialogo_editar_cantidad.dart';
import 'elegir_tarjeta.dart';
import 'venta_controlador.dart';

/// Medidas de Venta según el tamaño de la ventana. A 1920×1040 (el área del mock) son las del CSS; con poca altura se
/// compacta lo de cobro para que siga entrando entero.
class MedidasVenta {
  MedidasVenta(Size s)
      : margen = margenLateral(s.width),
        anchoPanel = (s.width * 0.3229).clamp(440.0, 620.0),
        compacto = s.height < 860;

  final double margen;
  final double anchoPanel;
  final bool compacto;

  double get altoBuscador => compacto ? 60 : 72;
  double get altoTarjeta => compacto ? 128 : 150;
  double get tamanioTotal => compacto ? 50 : 76;
  double get altoMedio => compacto ? 54 : 72;
  double get altoCobrar => compacto ? 60 : 78;
  double get huecoPanel => compacto ? 8 : 14;
}

class VistaVenta extends StatelessWidget {
  const VistaVenta({super.key, required this.onPagarProveedor, required this.onImprimir});

  final VoidCallback onPagarProveedor;

  /// Reimprimir la última venta cobrada (aparece en el carrito vacío, junto al acuse).
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final m = MedidasVenta(MediaQuery.sizeOf(context));
    return Padding(
      padding: EdgeInsets.fromLTRB(m.margen, separacionBajoNavbar, m.margen, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ColumnaProductos(m: m, onPagarProveedor: onPagarProveedor)),
          const SizedBox(width: 24),
          SizedBox(width: m.anchoPanel, child: _PanelCobro(m: m, onImprimir: onImprimir)),
        ],
      ),
    );
  }
}

// ══════════════════════════════ izquierda ══════════════════════════════

class _ColumnaProductos extends StatelessWidget {
  const _ColumnaProductos({required this.m, required this.onPagarProveedor});
  final MedidasVenta m;
  final VoidCallback onPagarProveedor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilaBuscador(m: m, onPagarProveedor: onPagarProveedor),
        SizedBox(height: m.compacto ? 12 : 18),
        Expanded(child: RejillaProductos(m: m)),
      ],
    );
  }
}

/// `.vsw`: el campo único y "Pagar proveedor"; el desplegable (`.drop`) cuelga de los dos, a todo el ancho de la fila.
class _FilaBuscador extends StatefulWidget {
  const _FilaBuscador({required this.m, required this.onPagarProveedor});
  final MedidasVenta m;
  final VoidCallback onPagarProveedor;

  @override
  State<_FilaBuscador> createState() => _FilaBuscadorState();
}

class _FilaBuscadorState extends State<_FilaBuscador> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // Mostrado una sola vez: el builder decide en cada cuadro si dibuja algo (llamar a show/hide en el build dispararía
    // un setState en medio de la construcción).
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final m = widget.m;
    return LayoutBuilder(
      builder: (context, limites) => OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final mostrar = c.hayTexto || c.avisoBusqueda != null;
          if (!mostrar) return const SizedBox.shrink();
          return CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 10),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: limites.maxWidth,
                // `up` del mock: el desplegable sube 18 px al abrirse; escribir no lo vuelve a animar.
                child: Aparecer.arriba(child: _Desplegable(controlador: c)),
              ),
            ),
          );
        },
        child: CompositedTransformTarget(
          link: _link,
          child: SizedBox(
            height: m.altoBuscador,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CampoUnico(controlador: c, alto: m.altoBuscador)),
                const SizedBox(width: 12),
                Btn(
                  'Pagar proveedor',
                  key: const Key('boton_pagar_proveedor'),
                  variante: VarBtn.dark,
                  icono: Ic.truck,
                  kbd: 'Alt+P',
                  alto: m.altoBuscador,
                  tamanioTexto: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  tooltip: 'Pagar a un proveedor (Alt+P)',
                  onTap: widget.onPagarProveedor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que hace Enter en el campo único: con texto agrega lo elegido del desplegable; vacío, cobra. Agregar y cobrar
/// devuelven el foco al campo (es seguir vendiendo); un diálogo secundario (Varios) no (El dueño, 2026-09-16).
Future<void> enterEnCampoUnico(BuildContext context, VentaControlador c) async {
  if (c.hayTexto) {
    if (c.coincidencias.isEmpty) return;
    if (c.coincidencias[c.indicePreseleccionado].esVarios) {
      await agregarVarios(context, c);
      return;
    }
    c.agregarSeleccionActual();
  } else {
    await cobrarOAbrirPosnet(context, c);
  }
  c.focoCampoPrincipal.requestFocus();
}

/// `.sbig`: la píldora gris de 72 px con la lupa; enfocada se pone blanca con el aro azul. Vacía y sin foco, la pista
/// se "tipea" sola mostrando lo que se puede escribir.
class _CampoUnico extends StatefulWidget {
  const _CampoUnico({required this.controlador, required this.alto});
  final VentaControlador controlador;
  final double alto;

  @override
  State<_CampoUnico> createState() => _CampoUnicoState();
}

class _CampoUnicoState extends State<_CampoUnico> {
  static const _pistas = ['Escaneá un código o buscá un producto', '200 queso barra', 'coca 2,25 l', '7790001000011'];
  String _pista = _pistas.first;
  Timer? _tipeo;
  int _i = 0, _j = 0, _dir = 1;

  FocusNode get _foco => widget.controlador.focoCampoPrincipal;

  @override
  void initState() {
    super.initState();
    _foco.addListener(_refrescar);
    widget.controlador.campoTexto.addListener(_refrescar);
    if (bucleHabilitado) _tipeo = Timer(ms(900), _tic);
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  // `typePlaceholder` del mock: escribe a 48 ms por letra, espera 1,7 s, borra de a dos letras y pasa a la siguiente.
  void _tic() {
    if (!mounted) return;
    if (!hayMovimiento(context) || _foco.hasFocus || widget.controlador.campoTexto.text.isNotEmpty) {
      if (_pista != _pistas.first) setState(() => _pista = _pistas.first);
      _i = 0;
      _j = 0;
      _dir = 1;
      _tipeo = Timer(ms(1200), _tic);
      return;
    }
    final s = _pistas[_i];
    if (_dir > 0) {
      _j++;
      setState(() => _pista = '${s.substring(0, _j.clamp(0, s.length))}|');
      if (_j >= s.length) {
        _dir = -1;
        _tipeo = Timer(ms(1700), _tic);
      } else {
        _tipeo = Timer(ms(48), _tic);
      }
      return;
    }
    _j -= 2;
    if (_j <= 0) {
      _j = 0;
      _dir = 1;
      _i = (_i + 1) % _pistas.length;
      setState(() => _pista = '|');
      _tipeo = Timer(ms(300), _tic);
      return;
    }
    setState(() => _pista = '${s.substring(0, _j)}|');
    _tipeo = Timer(ms(22), _tic);
  }

  @override
  void dispose() {
    _tipeo?.cancel();
    _foco.removeListener(_refrescar);
    widget.controlador.campoTexto.removeListener(_refrescar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = widget.controlador;
    final enfocado = _foco.hasFocus;
    final grande = widget.alto >= 70;
    final estiloTexto = estilo(grande ? 22 : 20, 450, color: p.tinta, em: -.02);
    return GestureDetector(
      onTap: _foco.requestFocus,
      excludeFromSemantics: true,
      child: AnimatedContainer(
        duration: ms(250),
        padding: EdgeInsets.symmetric(horizontal: grande ? 30 : 24),
        decoration: BoxDecoration(
          color: enfocado ? p.papel : p.s,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enfocado ? const [BoxShadow(color: PaletaMock.foco, spreadRadius: 3)] : null,
        ),
        child: Row(
          children: [
            Icono(Ic.search, size: grande ? 28 : 24, color: p.tinta),
            const SizedBox(width: 16),
            Expanded(
              child: AreaMinimaToque(
                child: TextField(
                key: const Key('campo_unico'),
                controller: c.campoTexto,
                focusNode: _foco,
                autofocus: true,
                style: estiloTexto,
                cursorColor: p.azul,
                decoration: decoracionSinBorde(_pista, estiloTexto.copyWith(color: p.mute)),
                onSubmitted: (_) => enterEnCampoUnico(context, c),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.drop`: resultados de lo escrito (6–7 filas antes de scrollear), "Sin coincidencias", o el aviso de un pesable.
class _Desplegable extends StatelessWidget {
  const _Desplegable({required this.controlador});
  final VentaControlador controlador;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = controlador;
    final hijos = <Widget>[];
    if (c.avisoBusqueda != null) {
      hijos.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
        child: Text(c.avisoBusqueda!, style: estilo(18, 500, color: p.b)),
      ));
    }
    if (c.hayTexto) {
      if (c.sinCoincidencias) {
        hijos.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          child: Text('Sin coincidencias', style: estilo(20, 400, color: p.mute)),
        ));
      } else if (c.productoSinStockEncontrado case final producto?) {
        hijos.add(Opacity(
          opacity: .5,
          child: _FilaResultado(producto: producto, gramos: null, elegida: false, agotado: true, categorias: c.categorias, onTap: null),
        ));
      } else {
        final gramos = interpretarTexto(c.campoTexto.text).gramos;
        hijos.add(ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 7 * 72.0),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: c.coincidencias.length,
            itemBuilder: (context, i) {
              final prod = c.coincidencias[i];
              return _FilaResultado(
                producto: prod,
                gramos: gramos,
                elegida: i == c.indicePreseleccionado,
                agotado: !tieneStock(prod),
                categorias: c.categorias,
                onTap: () async {
                  if (prod.esVarios) {
                    await agregarVarios(context, c);
                  } else {
                    c.agregarDesdeBusqueda(prod);
                    c.focoCampoPrincipal.requestFocus();
                  }
                },
              );
            },
          ),
        ));
      }
    }
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const Key('dropdown_resultados_busqueda'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.papel,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: p.pelo),
          boxShadow: const [BoxShadow(color: Color(0x380D1017), blurRadius: 80, offset: Offset(0, 30))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
      ),
    );
  }
}

String _nombreCategoria(List<Categoria> categorias, int? id) {
  if (id == null) return '';
  for (final c in categorias) {
    if (c.id == id) return c.nombre;
  }
  return '';
}

/// Avatar con la inicial y el par de colores del rubro (`NS.CATC`).
Widget _avatarProducto(Producto prod, List<Categoria> categorias, {double diametro = 44, double letra = 17}) {
  final (fondo, tinta) = parDeRubro(_nombreCategoria(categorias, prod.categoriaId), indice: prod.categoriaId ?? 0);
  return Avatar(prod.nombre, fondo: fondo, color: tinta, diametro: diametro, tamanioTexto: letra);
}

class _FilaResultado extends StatelessWidget {
  const _FilaResultado({
    required this.producto,
    required this.gramos,
    required this.elegida,
    required this.agotado,
    required this.categorias,
    required this.onTap,
  });

  final Producto producto;
  final int? gramos;
  final bool elegida;
  final bool agotado;
  final List<Categoria> categorias;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final String stock;
    final String precio;
    String? sufijo;
    if (producto.esVarios) {
      stock = '';
      precio = '—';
    } else if (producto.esPesable) {
      final porKilo = producto.precioPorKiloCentavos;
      if (gramos != null) {
        stock = '';
        precio = porKilo == null ? '—' : pesos(subtotalPesable(montoPorKiloCentavos: porKilo, gramos: gramos!));
        sufijo = ' por $gramos g';
      } else {
        final g = producto.stockGramos ?? 0;
        stock = agotado ? 'Sin stock' : '${(g / 1000).toStringAsFixed(1).replaceAll('.', ',')} kg';
        precio = porKilo == null ? '—' : '${pesos(porKilo)}/kg';
      }
    } else {
      stock = agotado ? 'Sin stock' : '${producto.stock} u.';
      precio = producto.precioCentavos == null ? '—' : pesos(producto.precioCentavos!);
    }
    return AlPasar(
      builder: (encima) => Tocable(
        onTap: agotado ? null : onTap,
        radio: 26,
        child: AnimatedContainer(
          duration: ms(150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(color: elegida || encima ? p.s : p.s.withValues(alpha: 0), borderRadius: BorderRadius.circular(26)),
          child: Row(
            children: [
              _avatarProducto(producto, categorias, diametro: 40, letra: 16),
              const SizedBox(width: 16),
              Expanded(child: Text(producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(21, 450, color: p.tinta))),
              const SizedBox(width: 16),
              if (stock.isNotEmpty) Text(stock, style: estilo(15, 400, color: p.mute, num: true)),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: precio, style: estilo(21, 600, color: p.tinta, num: true)),
                    if (sufijo != null) TextSpan(text: sufijo, style: estilo(13, 500, color: p.mute)),
                  ]),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtro de la grilla: "Más vendidos" (null), "Todos", una categoría o "Otros" (sin categoría).
final Object _todos = Object();
final Object _otros = Object();

/// `.vcats` + `.vgrid`: chips de categoría y tarjetas de producto (5 columnas a 1920). Tocar una tarjeta la agrega;
/// las que están en el carrito se pintan de azul con su cantidad.
class RejillaProductos extends StatefulWidget {
  const RejillaProductos({super.key, required this.m});
  final MedidasVenta m;

  @override
  State<RejillaProductos> createState() => _RejillaProductosState();
}

class _RejillaProductosState extends State<RejillaProductos> {
  Object? _filtro;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    final catalogo = c.catalogoVisible;
    final idsConProductos = catalogo.map((x) => x.categoriaId).toSet();
    final categorias = c.categorias.where((cat) => idsConProductos.contains(cat.id)).toList();
    final hayOtros = idsConProductos.contains(null);
    final porId = {for (final x in catalogo) x.id: x};
    final masVendidos = [for (final id in c.idsMasVendidos) ?porId[id]];

    final List<Producto> productos;
    if (_filtro == null) {
      productos = masVendidos.isNotEmpty ? masVendidos : catalogo;
    } else if (identical(_filtro, _todos)) {
      productos = catalogo;
    } else if (identical(_filtro, _otros)) {
      productos = catalogo.where((x) => x.categoriaId == null).toList();
    } else {
      productos = catalogo.where((x) => x.categoriaId == _filtro).toList();
    }

    // Lo que hay en el carrito, por producto: la tarjeta lo muestra en su contador.
    final enCarrito = <String, String>{};
    for (final l in c.carrito) {
      if (l.esVarios) continue;
      enCarrito[l.productoId] = switch (l) {
        LineaVentaPorUnidad u => '${u.cantidad}',
        LineaVentaPesable g => '${g.gramos} g',
      };
    }

    Widget chip(String texto, Object? filtro) => ChipMock(
          texto,
          elegido: identical(_filtro, filtro) || (filtro is int && _filtro == filtro),
          onTap: () => setState(() => _filtro = filtro),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, w) in [
                      chip('Más vendidos', null),
                      chip('Todos', _todos),
                      for (final cat in categorias) chip(cat.nombre, cat.id),
                      if (hayOtros) chip('Otros', _otros),
                    ].indexed) ...[if (i > 0) const SizedBox(width: 8), w],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ChipMock(
              'Varios',
              key: const Key('pildora_varios'),
              kbd: 'Alt+V',
              colorTexto: p.mute,
              tooltip: 'Un monto suelto para lo que no está cargado (Alt+V)',
              onTap: () => agregarVarios(context, c),
            ),
          ],
        ),
        SizedBox(height: widget.m.compacto ? 12 : 18),
        Expanded(
          child: productos.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      _filtro == null ? 'Todavía no hay historial de ventas.' : 'Sin productos en esta categoría',
                      style: estilo(17, 400, color: p.mute),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, limites) {
                    // 5 columnas en los 1164 px del mock; entre 2 y 6 según el ancho.
                    final columnas = ((limites.maxWidth + 14) / 214).floor().clamp(2, 6);
                    final filas = (productos.length / columnas).ceil();
                    return ListView.builder(
                      key: ValueKey(_filtro ?? 'mas'),
                      padding: const EdgeInsets.fromLTRB(4, 4, 6, 14),
                      itemCount: filas,
                      itemBuilder: (context, fila) => Padding(
                        padding: EdgeInsets.only(bottom: fila == filas - 1 ? 0 : 14),
                        // `grid-auto-rows:max-content`: la fila mide lo que su tarjeta más alta.
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var k = 0; k < columnas; k++) ...[
                                if (k > 0) const SizedBox(width: 14),
                                Expanded(
                                  child: fila * columnas + k < productos.length
                                      ? Aparecer.tarjeta(
                                          orden: fila * columnas + k,
                                          child: _Tarjeta(
                                            producto: productos[fila * columnas + k],
                                            contador: enCarrito['${productos[fila * columnas + k].id}'],
                                            categorias: c.categorias,
                                            altoMinimo: widget.m.altoTarjeta,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// `.tile`: avatar del rubro arriba, nombre y precio abajo, "Quedan N" con poco stock. En el carrito: azul claro con
/// aro azul y el contador arriba a la derecha, que late al cambiar.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.producto, required this.contador, required this.categorias, required this.altoMinimo});

  final Producto producto;
  final String? contador;
  final List<Categoria> categorias;
  final double altoMinimo;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pesable = producto.esPesable;
    final precio = pesable
        ? (producto.precioPorKiloCentavos == null ? '—' : pesos(producto.precioPorKiloCentavos!))
        : (producto.precioCentavos == null ? '—' : pesos(producto.precioCentavos!));
    final poco = !pesable && producto.stock > 0 && producto.stock < 15;
    final enCarrito = contador != null;
    final compacta = altoMinimo < 140;
    return AlPasar(
      builder: (encima) => Tocable(
        onTap: () {
          final c = context.read<VentaControlador>();
          c.agregarProducto(producto);
          c.focoCampoPrincipal.requestFocus();
        },
        radio: 30,
        etiqueta: 'Agregar ${producto.nombre}',
        child: Levantable(
          dy: 0,
          duracion: ms(450),
          builder: (context, _) => AnimatedContainer(
            duration: ms(300),
            constraints: BoxConstraints(minHeight: altoMinimo),
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: compacta ? 14 : 20),
            decoration: BoxDecoration(
              color: enCarrito ? p.azulClaro : (encima ? p.s2 : p.s),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: enCarrito ? p.azul : Colors.transparent, width: 2),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatarProducto(producto, categorias, diametro: compacta ? 36 : 44, letra: compacta ? 15 : 17),
                    const Spacer(),
                    SizedBox(height: compacta ? 6 : 10),
                    Text(producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(18, 500, color: p.tinta, alto: 1.2)),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(precio, style: estilo(compacta ? 22 : 25, 500, color: p.tinta, em: -.035, num: true)),
                        if (pesable) Text('/kg', style: estilo(14, 500, color: p.mute)),
                        if (poco)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: p.wbg, borderRadius: BorderRadius.circular(999)),
                            child: Text('Quedan ${producto.stock}', style: estilo(13, 600, color: p.w)),
                          ),
                      ],
                    ),
                  ],
                ),
                if (enCarrito)
                  Positioned(
                    top: compacta ? -2 : -4,
                    right: -4,
                    child: Pop(
                      valor: contador,
                      alMontar: true,
                      child: Container(
                        height: 30,
                        constraints: const BoxConstraints(minWidth: 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.azul, borderRadius: BorderRadius.circular(15)),
                        child: Text(contador!, style: estilo(14, 700, color: Colors.white, num: true)),
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

// ══════════════════════════════ derecha ══════════════════════════════

/// `.vder`: el panel gris de radio 52 con todo lo de cobrar.
class _PanelCobro extends StatelessWidget {
  const _PanelCobro({required this.m, required this.onImprimir});
  final MedidasVenta m;
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    return Container(
      padding: EdgeInsets.all(m.compacto ? 14 : 22),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(52)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Pestanas(),
          SizedBox(height: m.huecoPanel),
          Expanded(child: KeyedSubtree(key: const Key('carrito'), child: _Carrito(onImprimir: onImprimir))),
          SizedBox(height: m.huecoPanel),
          if (c.avisoCobro != null) ...[
            Text(c.avisoCobro!, textAlign: TextAlign.center, style: estilo(15, 600, color: p.b)),
            const SizedBox(height: 8),
          ],
          _Total(m: m),
          const SizedBox(height: 10),
          _Medios(m: m),
          const SizedBox(height: 10),
          _BotonCobrar(m: m),
          // El lugar de "Cobrar a mano" existe siempre (44 px): elegir QR o tarjeta no mueve nada de lugar. Con poca
          // altura el lugar aparece solo cuando hace falta, para dejarle más carrito a la vista.
          if (!m.compacto || (c.canalElegido != null && c.carrito.isNotEmpty)) ...[
            const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: c.canalElegido == null || c.carrito.isEmpty
                ? null
                : Btn(
                    'Cobrar a mano, sin terminal',
                    key: const Key('cobrar_a_mano'),
                    variante: VarBtn.out,
                    tam: TamBtn.sm,
                    ancho: true,
                    kbd: 'Alt+M',
                    onTap: () => cobrarAMano(context, c),
                  ),
          ),
          ],
        ],
      ),
    );
  }
}

/// `.vtabs`: "Venta 1 · 3" por cada venta abierta (con su × si hay más de una) y "+ Nueva · Alt+N".
class _Pestanas extends StatelessWidget {
  const _Pestanas();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    final resumen = c.resumenPestanas;
    final varias = resumen.length > 1;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  for (var i = 0; i < resumen.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _Pestana(
                      titulo: 'Venta ${i + 1}',
                      lineas: resumen[i].lineas,
                      elegida: i == c.pestanaActiva,
                      onTap: () => c.cambiarAPestana(i),
                    ),
                    if (varias)
                      Tocable(
                        onTap: () {
                          c.cambiarAPestana(i);
                          cancelarVentaConDeshacer(context, c);
                        },
                        radio: 11,
                        etiqueta: 'Cerrar Venta ${i + 1}',
                        tooltip: 'Descartar la venta ${i + 1}',
                        child: AlPasar(
                          builder: (encima) => Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(left: 2, right: 6),
                            decoration: BoxDecoration(color: encima ? p.bbg : p.bbg.withValues(alpha: 0), shape: BoxShape.circle),
                            child: Center(child: Icono(Ic.x, size: 12, color: encima ? p.b : p.soft, grosor: 2.8)),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tocable(
            key: const Key('nueva_venta'),
            onTap: c.carrito.isEmpty ? null : c.nuevaVenta,
            radio: 21,
            etiqueta: 'Nueva venta',
            tooltip: 'Nueva venta (Alt+N)',
            child: AlPasar(
              builder: (encima) => Opacity(
                opacity: c.carrito.isEmpty ? .5 : 1,
                child: AnimatedContainer(
                  duration: ms(200),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(color: encima && c.carrito.isNotEmpty ? p.s2 : p.s2.withValues(alpha: 0), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icono(Ic.plus, size: 16, color: p.mute, grosor: 2.6),
                      const SizedBox(width: 8),
                      Text('Nueva', style: estilo(15, 600, color: p.mute)),
                      const SizedBox(width: 8),
                      Kbd('Alt+N', color: p.mute),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({required this.titulo, required this.lineas, required this.elegida, required this.onTap});
  final String titulo;
  final int lineas;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AlPasar(
      builder: (encima) => Tocable(
        onTap: onTap,
        radio: 21,
        etiqueta: titulo,
        seleccionado: elegida,
        child: AnimatedContainer(
          duration: ms(200),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: elegida ? p.papel : (encima ? p.s2 : p.s2.withValues(alpha: 0)),
            borderRadius: BorderRadius.circular(999),
            boxShadow: elegida ? const [BoxShadow(color: Color(0x140D1017), blurRadius: 10, offset: Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: estilo(15, 600, color: elegida ? p.tinta : p.mute)),
              if (lineas > 0) ...[const SizedBox(width: 8), Text('$lineas', style: estilo(15, 500, color: p.mute, num: true))],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.cart`: las líneas (blancas, radio 28), la última con aro azul; vacío, el aro que late con "Escaneá un código...".
class _Carrito extends StatelessWidget {
  const _Carrito({required this.onImprimir});
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    if (c.carrito.isEmpty) {
      return _CarritoVacio(ventaId: c.ultimaVentaId, totalCentavos: c.ultimoTotalCobradoCentavos, onImprimir: onImprimir);
    }
    final ultima = c.indiceUltimaLinea;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      itemCount: c.carrito.length,
      findChildIndexCallback: (clave) {
        for (var i = 0; i < c.carrito.length; i++) {
          if (claveLineaCarrito(c.carrito[i], i) == clave) return i;
        }
        return null;
      },
      itemBuilder: (context, i) => Padding(
        key: claveLineaCarrito(c.carrito[i], i),
        padding: EdgeInsets.only(bottom: i == c.carrito.length - 1 ? 0 : 6),
        child: Aparecer.mensaje(child: _LineaCarrito(indice: i, linea: c.carrito[i], ultima: i == ultima)),
      ),
    );
  }
}

/// Una línea por producto; "Varios" puede repetirse, así que su clave lleva también la posición.
ValueKey<String> claveLineaCarrito(LineaVenta linea, int index) =>
    ValueKey('linea-${linea.productoId}${linea.esVarios ? '-$index' : ''}');

class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({required this.indice, required this.linea, required this.ultima});

  final int indice;
  final LineaVenta linea;
  final bool ultima;

  bool _sinStock(VentaControlador c) {
    final prod = c.productoPorId(linea.productoId);
    if (prod == null || prod.esVarios) return false;
    return switch (linea) {
      LineaVentaPesable g => (prod.stockGramos ?? 0) - g.gramos <= 0,
      LineaVentaPorUnidad u => prod.stock - u.cantidad <= 0,
    };
  }

  Future<void> _editar(BuildContext context, VentaControlador c) async {
    final l = linea;
    final nuevo = await mostrarDialogoEditarCantidad(
      context,
      titulo: l is LineaVentaPesable ? 'Gramos' : 'Cantidad',
      valorActual: l is LineaVentaPesable ? l.gramos : (l as LineaVentaPorUnidad).cantidad,
      linea: l,
    );
    if (nuevo == null) return;
    if (l is LineaVentaPesable) {
      c.editarGramosExacto(indice, nuevo);
    } else {
      c.editarCantidadExacta(indice, nuevo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.read<VentaControlador>();
    final l = linea;
    final unitario = switch (l) {
      LineaVentaPorUnidad u => '${pesos(u.precioUnitarioCentavos)} c/u',
      LineaVentaPesable g => '${pesos(g.precioPorKiloCentavos)} el kilo',
    };
    final cantidad = switch (l) {
      LineaVentaPorUnidad u => '${u.cantidad}',
      LineaVentaPesable g => '${g.gramos} g',
    };
    final pesable = l is LineaVentaPesable;
    return LayoutBuilder(
      builder: (context, limites) {
        final angosta = limites.maxWidth < 420;
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
          decoration: BoxDecoration(
            color: p.papel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: ultima ? p.azul : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.nombreProducto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(17, 500, color: _sinStock(c) ? p.b : p.tinta, alto: 1.2)),
                    if (!l.esVarios) Padding(padding: const EdgeInsets.only(top: 2), child: Text(unitario, style: estilo(13, 400, color: p.soft, num: true))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Pop(
                valor: cantidad,
                child: _Stepper(
                  indice: indice,
                  texto: cantidad,
                  angosto: angosta,
                  onMenos: () => pesable ? c.ajustarGramos(indice, -1) : c.ajustarCantidad(indice, -1),
                  onMas: () => pesable ? c.ajustarGramos(indice, 1) : c.ajustarCantidad(indice, 1),
                  onEditar: () => _editar(context, c),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: angosta ? 80 : 96),
                child: Text(pesos(l.subtotalCentavos), textAlign: TextAlign.right, style: estilo(19, 600, color: p.tinta, num: true)),
              ),
              const SizedBox(width: 8),
              AlPasar(
                key: Key('quitar_$indice'),
                builder: (encima) => Tocable(
                  onTap: () {
                    c.eliminarLinea(indice);
                    mostrarAviso(context, 'Quitaste ${l.nombreProducto}', textoAccion: 'Deshacer', alAccionar: () => c.restaurarLinea(indice, l));
                  },
                  radio: 18,
                  etiqueta: 'Quitar ${l.nombreProducto}',
                  child: AnimatedContainer(
                    duration: ms(150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: encima ? p.bbg : p.bbg.withValues(alpha: 0), shape: BoxShape.circle),
                    child: Center(child: Icono(Ic.trash, size: 19, color: encima ? p.b : p.soft)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// `.stp`: − número + en una cápsula gris; doble clic en el número para escribir el valor exacto.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.indice, required this.texto, required this.angosto, required this.onMenos, required this.onMas, required this.onEditar});

  final int indice;
  final String texto;
  final bool angosto;
  final VoidCallback onMenos;
  final VoidCallback onMas;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget boton(Ic ic, String etiqueta, VoidCallback onTap) => AlPasar(
          builder: (encima) => Tocable(
            onTap: onTap,
            radio: 17,
            etiqueta: etiqueta,
            child: AnimatedContainer(
              duration: ms(150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: encima ? p.s3 : p.s3.withValues(alpha: 0), shape: BoxShape.circle),
              child: Center(child: Icono(ic, size: 14, color: p.tinta, grosor: 2.6)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(key: Key('restar_$indice'), child: boton(Ic.minus, 'Restar uno', onMenos)),
          const SizedBox(width: 2),
          GestureDetector(
            onDoubleTap: onEditar,
            child: Tooltip(
              message: 'Doble clic para escribir la cantidad',
              waitDuration: ms(800),
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: angosto ? 44 : 54),
                  child: Text(texto, key: Key('cantidad_$indice'), textAlign: TextAlign.center, style: estilo(16, 600, color: p.tinta, num: true)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          KeyedSubtree(key: Key('sumar_$indice'), child: boton(Ic.plus, 'Sumar uno', onMas)),
        ],
      ),
    );
  }
}

/// `.empty` del carrito: el aro azul que late con el ícono de escanear. Después de cobrar, en su lugar, el acuse de la
/// venta (tilde que se dibuja + número y total + "Imprimir ticket"), que se va solo con la primera línea de la venta
/// siguiente: no bloquea, se puede seguir escaneando mientras está.
class _CarritoVacio extends StatelessWidget {
  const _CarritoVacio({required this.ventaId, required this.totalCentavos, required this.onImprimir});

  final int? ventaId;
  final int? totalCentavos;
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (ventaId != null && totalCentavos != null) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Aparecer(
          key: ValueKey('cobrada-$ventaId'),
          dy: 0,
          escala: .92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: p.gbg, shape: BoxShape.circle),
                child: Center(child: TildeDibujada(color: p.g, tamanio: 54)),
              ),
              const SizedBox(height: 14),
              Text(pesos(totalCentavos!), style: Tipos.fig(p.tinta, tamanio: 48)),
              const SizedBox(height: 6),
              Text('Venta #$ventaId cobrada', style: estilo(17, 400, color: p.mute)),
              const SizedBox(height: 14),
              Btn('Imprimir ticket', variante: VarBtn.ton, sobreGris: true, tam: TamBtn.sm, icono: Ic.print, onTap: onImprimir),
            ],
          ),
        ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, limites) => limites.maxHeight < 210 ? Center(
            child: Text('Escaneá un código o buscá un producto', textAlign: TextAlign.center, style: estilo(17, 400, color: p.mute)),
          ) : Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnilloPulso(color: p.azul, opacidad: .35),
                Icono(Ic.scan, size: 44, color: p.mute, grosor: 1.6),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Escaneá un código o buscá un producto\npara empezar la venta', textAlign: TextAlign.center, style: estilo(19, 400, color: p.mute, alto: 1.4)),
        ],
      ),
    ),
    );
  }
}

/// `.tot`: el bloque oscuro con "Total a cobrar", el botón de descuento, el número grande que cuenta y las cápsulas del
/// desglose (descuento, recargo de cigarrillos, redondeo, seña).
class _Total extends StatelessWidget {
  const _Total({required this.m});
  final MedidasVenta m;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    final r = c.resultado;
    final total = r?.totalCentavos ?? c.subtotalCentavos;
    final hayDescuento = c.campoDescuentoCtrl.text.trim().isNotEmpty;
    final chips = <String>[
      if (r != null && r.descuentoCentavos > 0) 'Descuento −${pesos(r.descuentoCentavos)}',
      if (r != null && r.recargoCigarrillosCentavos > 0) 'Recargo cigarrillos +${pesos(r.recargoCigarrillosCentavos)}',
      if (r != null && r.redondeoCentavos > 0) 'Redondeo +${pesos(r.redondeoCentavos)}',
      if (c.senaAplicadaCentavos > 0) 'Seña −${pesos(c.senaAplicadaCentavos)} · a cobrar ${pesos(c.aCobrarCentavos!)}',
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(30, m.compacto ? 14 : 20, 30, m.compacto ? 12 : 18),
      decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(44)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Total a cobrar', style: estilo(16, 600, color: p.heroSub))),
              AlPasar(
                builder: (encima) => Tocable(
                  key: const Key('boton_descuento'),
                  onTap: () => mostrarDialogoDescuento(context, c),
                  radio: 18,
                  child: AnimatedContainer(
                    duration: ms(200),
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(color: encima ? const Color(0x33FFFFFF) : p.heroChip, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icono(Ic.percent, size: 15, color: p.sobreHero, grosor: 2.2),
                        const SizedBox(width: 7),
                        Text(hayDescuento ? 'Cambiar descuento' : 'Descuento', style: estilo(14, 600, color: p.sobreHero)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: m.compacto ? 2 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroQueCuenta(
              key: const Key('total_venta'),
              valor: total,
              formato: pesos,
              contarAlAparecer: false,
              estilo: estilo(m.tamanioTotal, 450, color: p.sobreHero, em: -.06, alto: 1, num: true),
            ),
          ),
          SizedBox(height: m.compacto ? 4 : 6),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: m.compacto && chips.isEmpty ? 0 : 30),
            child: Wrap(
              key: const ValueKey('desglose'),
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final t in chips)
                  Aparecer(
                    key: ValueKey(t.split(' ').first),
                    dy: 4,
                    duracion: ms(250),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(color: p.heroChip, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(t, style: estilo(13.5, 600, color: p.sobreHero, num: true))]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.medios`: Efectivo, QR, Tarjeta y Mixto en 2×2. El elegido se llena con su color y late.
class _Medios extends StatelessWidget {
  const _Medios({required this.m});
  final MedidasVenta m;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    final virtual = c.medioElegido == ComposicionPago.virtual;
    final tarjeta = virtual && esCanalTarjeta(c.canalElegido);
    final etiquetaTarjeta = switch (virtual ? c.canalElegido : null) {
      canalDebito => 'Débito',
      canalCredito => 'Crédito 1 pago',
      _ => 'Tarjeta',
    };
    void volverAlCampo() => c.focoCampoPrincipal.requestFocus();
    Widget medio(String clave, String titulo, String atajo, Ic ic, Color color, bool elegido, VoidCallback onTap) => Expanded(
          child: _Medio(
            clave: clave,
            titulo: titulo,
            atajo: atajo,
            icono: ic,
            color: color,
            elegido: elegido,
            alto: m.altoMedio,
            onTap: onTap,
          ),
        );
    return Column(
      children: [
        Row(children: [
          medio('efectivo', 'Efectivo', 'ALT+E', Ic.cash, p.efe, c.medioElegido == ComposicionPago.efectivo, () {
            c.elegirMedio(ComposicionPago.efectivo);
            volverAlCampo();
          }),
          const SizedBox(width: 10),
          medio('qr', 'QR', 'ALT+Q', Ic.scan, p.mp, virtual && c.canalElegido == canalQr, () {
            c.elegirCanalDirecto(canalQr);
            volverAlCampo();
          }),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          medio('tarjeta', etiquetaTarjeta, 'ALT+D', Ic.card, p.tar, tarjeta, () => elegirTarjeta(context, c)),
          const SizedBox(width: 10),
          medio('mixto', 'Mixto', 'ALT+X', Ic.swap, p.mix, c.medioElegido == ComposicionPago.mixto, () => abrirMixto(context, c)),
        ]),
      ],
    );
  }
}

class _Medio extends StatelessWidget {
  const _Medio({
    required this.clave,
    required this.titulo,
    required this.atajo,
    required this.icono,
    required this.color,
    required this.elegido,
    required this.alto,
    required this.onTap,
  });

  final String clave;
  final String titulo;
  final String atajo;
  final Ic icono;
  final Color color;
  final bool elegido;
  final double alto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final texto = elegido ? Colors.white : p.tinta;
    final grande = alto >= 70;
    return Pop(
      valor: elegido,
      child: Levantable(
        builder: (context, _) => Tocable(
          key: Key('medio_$clave'),
          onTap: onTap,
          radio: 30,
          seleccionado: elegido,
          etiqueta: '$titulo ($atajo)',
          child: AnimatedContainer(
            duration: ms(300),
            curve: curvaEase,
            height: alto,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: elegido ? color : p.papel, borderRadius: BorderRadius.circular(30)),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: ms(300),
                  width: grande ? 46 : 40,
                  height: grande ? 46 : 40,
                  decoration: BoxDecoration(color: elegido ? const Color(0x38FFFFFF) : p.s, shape: BoxShape.circle),
                  child: Center(child: Icono(icono, size: 22, color: texto)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(20, 600, color: texto, em: -.02)),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Opacity(opacity: .55, child: Text(atajo, style: estilo(12, 600, color: texto, em: .05))),
                      ),
                    ],
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

/// `.cobrar`: la píldora azul de 78 px con "Cobrar · Enter" y el círculo con la flecha.
class _BotonCobrar extends StatelessWidget {
  const _BotonCobrar({required this.m});
  final MedidasVenta m;

  Future<void> _cobrar(BuildContext context, VentaControlador c) async {
    if (c.medioElegido == ComposicionPago.mixto && c.montoEfectivoMixtoCentavos == null) {
      await abrirMixto(context, c);
      if (!context.mounted) return;
      // `confirmarMixto` reclasifica el medio si el cliente terminó pagando todo de un lado: solo corta si el diálogo
      // se cerró sin confirmar (bug real, ver el historial de `columna_cobro.dart`).
      if (c.medioElegido == ComposicionPago.mixto && c.montoEfectivoMixtoCentavos == null) return;
    }
    await cobrarOAbrirPosnet(context, c);
    c.focoCampoPrincipal.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<VentaControlador>();
    final habilitado = c.carrito.isNotEmpty && c.medioElegido != null && !c.cobrando;
    final go = m.compacto ? 46.0 : 54.0;
    return Opacity(
      opacity: habilitado ? 1 : .38,
      child: Levantable(
        habilitado: habilitado,
        builder: (context, encima) => Tocable(
          key: const Key('boton_cobrar'),
          onTap: habilitado ? () => _cobrar(context, c) : null,
          radio: m.altoCobrar / 2,
          etiqueta: 'Cobrar (Enter)',
          child: AnimatedContainer(
            duration: ms(300),
            height: m.altoCobrar,
            padding: const EdgeInsets.fromLTRB(38, 0, 14, 0),
            decoration: BoxDecoration(
              color: encima ? p.azulOscuro : p.azul,
              borderRadius: BorderRadius.circular(999),
              boxShadow: encima ? const [BoxShadow(color: Color(0x592F5BE8), blurRadius: 40, offset: Offset(0, 18))] : null,
            ),
            child: Row(
              children: [
                Text('Cobrar', style: estilo(24, 600, color: Colors.white)),
                const SizedBox(width: 12),
                const Kbd('Enter', color: Colors.white, tamanio: 13),
                const Spacer(),
                Container(
                  width: go,
                  height: go,
                  decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                  child: const Center(child: Icono(Ic.arrow, size: 26, color: Colors.white, grosor: 2.3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
