// Cobrar en un negocio de servicios (`REGLAS-NEGOCIO.md` §20; mock `docs/mock-servicios`, "Cobrar"): en vez de buscar o
// escanear productos, una grilla con los servicios por categoría. Tocar uno lo suma al carrito con su precio y con lo que
// cuestan hoy sus insumos como costo-foto (Regla 4; la mano de obra no entra en la ganancia). Si con el stock de hoy no
// alcanza un insumo, se avisa y se cobra igual (por defecto solo avisa).
//
// Lee la base del celular, como la pestaña Servicios: cobrar servicios es solo para "Solo celular" (etapa 3).
//
// Los productos que el negocio vende aparte (El dueño, 2026-10-14) se eligen de una lista con buscador
// ([ListaProductosParaCobrarNs]) y se venden igual sin stock, con aviso (`avisoDeStockAlVender`). En Nodo Gastro van en la
// misma grilla que los platos, con los combos.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show listarCategorias;
import '../../data/repositorio_promos.dart' show PromoConComponentes, listarPromos;
import '../../data/repositorio_servicios.dart';
import '../../data/repositorio_ventas.dart' show lineaDesdeProducto;
import '../../domain/normalizacion_texto.dart' show normalizarTexto;
import '../../domain/modulos.dart';
import '../../domain/venta.dart';
import '../../servicios/modulos_activos.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../kit/kit_ns.dart';

/// La línea de venta de un servicio: una vez, con su precio y el costo de sus insumos de hoy.
LineaVentaPorUnidad lineaDeServicio(ServicioListado s) => LineaVentaPorUnidad(
      productoId: '${s.producto.id}',
      nombreProducto: s.producto.nombre,
      proveedorId: null,
      cantidad: 1,
      esVarios: false,
      tipoCigarrillo: TipoCigarrillo.ninguno,
      precioUnitarioCentavos: s.producto.precioCentavos ?? 0,
      costoUnitarioCentavos: s.costo.insumosCentavos,
    );

/// El aviso de un servicio que con el stock de hoy no alcanza, o null si alcanza (o no lleva la cuenta de insumos).
String? avisoDeInsumos(ServicioListado s) {
  if (!moduloActivo(Modulo.insumos)) return null;
  final alcanza = s.alcanzaPara;
  if (alcanza == null || alcanza >= 1) return null;
  final falta = s.seAcabaPrimero?.producto.nombre;
  return falta == null ? 'No alcanzan los insumos' : 'Falta ${falta.toLowerCase()}';
}

class GrillaServiciosNs extends StatefulWidget {
  /// [db] es para tests. Con [onElegirProducto] (Nodo Gastro) la grilla trae también las bebidas y los combos: todo lo de
  /// la carta en un solo lugar, sin un botón aparte para cada cosa (El dueño, 2026-10-23).
  const GrillaServiciosNs({super.key, required this.onElegir, this.onElegirProducto, this.db});

  final ValueChanged<ServicioListado> onElegir;
  final ValueChanged<Producto>? onElegirProducto;
  final AppDatabase? db;

  @override
  State<GrillaServiciosNs> createState() => _GrillaServiciosNsState();
}

/// Un mosaico de la grilla: un plato (o servicio), una bebida o un combo.
class _Mosaico {
  const _Mosaico({required this.clave, required this.nombre, required this.precio, required this.categoria, required this.onTap, this.detalle, this.aviso});
  final Key clave;
  final String nombre;
  final int precio;
  final String categoria;
  final VoidCallback onTap;
  final String? detalle;
  final String? aviso;
}

class _GrillaServiciosNsState extends State<GrillaServiciosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<ServicioListado>? _servicios;
  List<Producto> _productos = const [];
  List<PromoConComponentes> _combos = const [];
  Map<int, String> _categorias = const {};
  String? _categoria;
  final _buscar = TextEditingController();
  StreamSubscription<void>? _sub;

  bool get _conCarta => widget.onElegirProducto != null;

  @override
  void initState() {
    super.initState();
    _sub = avisosCambiosCompanion.listen((_) => _cargar());
    _cargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final r = await Future.wait([
      listarServicios(_db, conManoDeObra: false),
      listarCategorias(_db),
      if (_conCarta) listarProductosDeVenta(_db),
      if (_conCarta && moduloActivo(Modulo.promos)) listarPromos(_db, soloActivas: true),
    ]);
    if (!mounted) return;
    setState(() {
      _servicios = [for (final s in r[0] as List<ServicioListado>) if ((s.producto.precioCentavos ?? 0) > 0) s];
      _categorias = {for (final c in r[1] as List<Categoria>) c.id: c.nombre};
      if (r.length > 2) _productos = [for (final p in r[2] as List<Producto>) if (!p.esPesable && (p.precioCentavos ?? 0) > 0) p];
      if (r.length > 3) _combos = r[3] as List<PromoConComponentes>;
    });
  }

  String _categoriaDe(ServicioListado s) => _categorias[s.producto.categoriaId] ?? (_conCarta ? 'Platos' : 'Sin categoría');

  List<_Mosaico> get _mosaicos => [
        for (final s in _servicios!)
          _Mosaico(
            clave: ValueKey('cobrar-servicio-${s.producto.id}'),
            nombre: s.producto.nombre,
            precio: s.producto.precioCentavos ?? 0,
            categoria: _categoriaDe(s),
            onTap: () => widget.onElegir(s),
            // Lo que tarda un plato no le sirve a quien cobra; lo que dura un servicio, sí (arma la agenda).
            detalle: _conCarta ? null : '${s.producto.duracionMinutos ?? 0} min',
            aviso: avisoDeInsumos(s),
          ),
        for (final p in _productos)
          _Mosaico(
            clave: ValueKey('cobrar-producto-${p.id}'),
            nombre: p.nombre,
            precio: p.precioCentavos ?? 0,
            categoria: _categorias[p.categoriaId] ?? 'Bebidas y otros',
            onTap: () => widget.onElegirProducto!(p),
            aviso: p.stock <= 0 ? 'Sin stock' : null,
          ),
        for (final c in _combos)
          _Mosaico(
            clave: ValueKey('cobrar-combo-${c.promo.id}'),
            nombre: c.promo.nombre,
            precio: c.promo.precioCentavos ?? 0,
            categoria: 'Combos',
            // El stock que alcanza viaja en el producto: así "Cobrar" avisa si falta una bebida, como con las sueltas.
            onTap: () => widget.onElegirProducto!(c.promo.copyWith(stock: c.stock)),
            aviso: c.stock <= 0 ? 'Sin stock' : null,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    if (_servicios == null) return const EsqueletoListaNs();
    final todos = _mosaicos;
    if (todos.isEmpty) {
      return InfoNs(_conCarta
          ? 'Todavía no hay nada en la carta con precio. Cargalo en la pestaña Carta y aparece acá para vender.'
          : 'Todavía no hay servicios con precio. Cargalos en la pestaña Servicios y aparecen acá para cobrar.');
    }
    final categorias = {for (final m in todos) m.categoria}.toList();
    final texto = normalizarTexto(_buscar.text.trim());
    final visibles = [
      for (final m in todos)
        if ((_categoria == null || m.categoria == _categoria) && (texto.isEmpty || normalizarTexto(m.nombre).contains(texto))) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Con una carta larga, buscar es más rápido que recorrer las categorías.
        if (todos.length > 12) ...[
          BuscadorNs(controller: _buscar, placeholder: 'Buscar en la carta', onChanged: (_) => setState(() {}), conBorrar: _buscar.text.isNotEmpty, onBorrar: () => setState(_buscar.clear)),
          const SizedBox(height: 12),
        ],
        if (categorias.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChipNs(texto: 'Todos', activo: _categoria == null, onTap: () => setState(() => _categoria = null)),
              for (final c in categorias) ChipNs(texto: c, activo: _categoria == c, onTap: () => setState(() => _categoria = c)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (visibles.isEmpty)
          const InfoNs('Sin coincidencias')
        else
          // Dos columnas en el celular; en la compu (Cobrar a lo ancho) entran más, del mismo tamaño que en el celular.
          LayoutBuilder(builder: (context, caja) => GridView.count(
            crossAxisCount: (caja.maxWidth / 200).floor().clamp(2, 6),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 165 / 96,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final m in visibles)
                PresionNs(
                  key: m.clave,
                  onTap: m.onTap,
                  etiqueta: m.nombre,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(m.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, altura: 1.2, color: ns.ink)),
                        Row(
                          children: [
                            Expanded(child: Text(plataNs(m.precio), style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, tabular: true))),
                            if (m.detalle != null) Text(m.detalle!, style: estiloNs(13, color: ns.mute)),
                          ],
                        ),
                        if (m.aviso != null)
                          Text(m.aviso!, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(12, peso: FontWeight.w600, color: ns.w)),
                      ],
                    ),
                  ),
                ),
            ],
          )),
      ],
    );
  }
}

/// La línea de venta de un producto: una unidad, con su precio y su costo de hoy (Regla 2, `lineaDesdeProducto`).
LineaVenta lineaDeProducto(Producto p) => lineaDesdeProducto(p, cantidad: 1);

/// Los productos para sumar al cobro, con buscador. Sin pesables ni productos sin precio: en un negocio de servicios se
/// venden por unidad, y un pesable heredado del almacén pediría gramos.
class ListaProductosParaCobrarNs extends StatefulWidget {
  /// [db] es para tests.
  const ListaProductosParaCobrarNs({super.key, required this.onElegir, this.db});

  final ValueChanged<Producto> onElegir;
  final AppDatabase? db;

  @override
  State<ListaProductosParaCobrarNs> createState() => _ListaProductosParaCobrarNsState();
}

class _ListaProductosParaCobrarNsState extends State<ListaProductosParaCobrarNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  final _buscar = TextEditingController();
  List<Producto>? _productos;

  @override
  void initState() {
    super.initState();
    listarProductosDeVenta(_db).then((r) {
      if (mounted) setState(() => _productos = [for (final p in r) if (!p.esPesable && (p.precioCentavos ?? 0) > 0) p]);
    });
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final productos = _productos;
    if (productos == null) return const EsqueletoListaNs();
    if (productos.isEmpty) {
      return const InfoNs('Todavía no hay productos para vender. Cargalos en la pestaña Servicios, solapa Productos.');
    }
    final texto = normalizarTexto(_buscar.text.trim());
    final visibles = [for (final p in productos) if (texto.isEmpty || normalizarTexto(p.nombre).contains(texto)) p];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (productos.length > 6) ...[
          CampoNs(etiqueta: 'Buscar', controller: _buscar, placeholder: 'Ej.: shampoo', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
        ],
        if (visibles.isEmpty)
          const InfoNs('Sin coincidencias')
        else
          ListaAgrupadaNs(
            filas: [
              for (final p in visibles)
                TarjetaFilaNs(
                  key: ValueKey('cobrar-producto-${p.id}'),
                  titulo: p.nombre,
                  subtitulo: p.stock <= 0 ? 'Sin stock' : (p.stock == 1 ? 'Queda 1' : 'Quedan ${p.stock}'),
                  chevron: false,
                  radio: 0,
                  onTap: () => widget.onElegir(p),
                  derecha: Text(plataNs(p.precioCentavos ?? 0), style: estiloNs(16, peso: FontWeight.w600, color: ns.ink, tabular: true)),
                ),
            ],
          ),
      ],
    );
  }
}
