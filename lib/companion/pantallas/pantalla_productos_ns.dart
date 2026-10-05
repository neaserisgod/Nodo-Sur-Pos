// Productos, tal cual el mock (docs/03 B3): título con campana y "+ Nuevo", el botón
// negro de "Controlar stock", el buscador, los filtros combinables (uno solo activo a
// la vez en toda la fila), la lista agrupada con el precio a la derecha, "Elegir
// varios" con su barra de lote, y la vista "Controlar stock" para contar por proveedor.
// Además de los filtros del mock quedan los de higiene de catálogo que la app ya tenía
// (sin proveedor, sin costo, sin categoría, sin código de barras).

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_ns.dart';
import '../cambios_companion.dart';
import '../cliente_companion.dart';
import '../escanear_codigo.dart';
import '../funciones_ns.dart' show normalizarNs;
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../pantalla_conteo_stock.dart';
import '../pantalla_formulario_producto.dart';
import '../servicio_companion.dart';
import 'hoja_cambiar_precio_ns.dart';
import 'hoja_lote_ns.dart';
import 'pantalla_notificaciones_ns.dart';

enum _Filtro { todos, sinStock, pocoStock, proveedor, sinProveedor, sinCosto, sinCategoria, sinCodigo }

class PantallaProductosNs extends StatefulWidget {
  const PantallaProductosNs({super.key});

  @override
  State<PantallaProductosNs> createState() => _PantallaProductosNsState();
}

class _PantallaProductosNsState extends State<PantallaProductosNs> {
  final _busqueda = TextEditingController();
  List<ProductoCompanion> _todos = [];
  List<ProveedorCompanion> _proveedores = [];
  List<CategoriaCompanion> _categorias = [];
  _Filtro _filtro = _Filtro.todos;
  int? _proveedorId;
  bool _eligiendo = false;
  final Set<int> _marcados = {};
  bool _cargando = true;
  ServicioCompanion? _servicioCargado;
  String? _error;
  StreamSubscription<void>? _sub;
  ControladorAppNs? _app;

  @override
  void initState() {
    super.initState();
    _sub = avisosCambiosCompanion.listen((_) => _cargar(silencioso: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppNs.of(context);
    _app = app;
    // El servicio se resuelve después de abrir el menú: se carga apenas aparece (y de nuevo si cambia, por ejemplo al
    // pasar de la PC a la base del celular).
    final servicio = app.servicio;
    if (servicio != null && !identical(servicio, _servicioCargado)) {
      _servicioCargado = servicio;
      _cargar();
    }
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final servicio = AppNs.of(context).servicio;
    if (servicio == null) return;
    if (!silencioso) setState(() => _cargando = true);
    try {
      final r = await Future.wait([servicio.productos(), servicio.proveedores(), servicio.categorias()]);
      if (mounted) {
        setState(() {
          _todos = r[0] as List<ProductoCompanion>;
          _proveedores = r[1] as List<ProveedorCompanion>;
          _categorias = r[2] as List<CategoriaCompanion>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  String? _nombreProveedor(int? id) => _proveedores.where((p) => p.id == id).firstOrNull?.nombre;

  /// Lo que dice la lista cuando no hay nada para mostrar (mock `noProdMsg`).
  String get _mensajeVacio {
    if (_busqueda.text.trim().isNotEmpty) return 'Sin resultados';
    return switch (_filtro) {
      _Filtro.sinProveedor => 'Ningún producto sin proveedor',
      _Filtro.sinCosto => 'Ningún producto sin costo',
      _Filtro.sinCategoria => 'Ningún producto sin categoría',
      _Filtro.sinCodigo => 'Ningún producto sin código de barras',
      _Filtro.proveedor => 'Este proveedor no tiene productos cargados',
      _Filtro.sinStock || _Filtro.pocoStock => 'No hay productos con ese filtro',
      _Filtro.todos => 'Todavía no hay productos cargados',
    };
  }

  int get _nSinStock => _todos.where(sinStockNs).length;
  int get _nPocoStock => _todos.where(pocoStockNs).length;

  List<ProductoCompanion> get _visibles {
    final q = normalizarNs(_busqueda.text);
    return [
      for (final p in _todos)
        if ((q.isEmpty || normalizarNs(p.nombre).contains(q) || (p.codigoBarras ?? '').contains(q.trim())) &&
            switch (_filtro) {
              _Filtro.todos => true,
              _Filtro.sinStock => sinStockNs(p),
              _Filtro.pocoStock => pocoStockNs(p),
              _Filtro.proveedor => p.proveedorId == _proveedorId,
              _Filtro.sinProveedor => p.proveedorId == null,
              _Filtro.sinCosto => (p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos) == null,
              _Filtro.sinCategoria => p.categoriaId == null,
              _Filtro.sinCodigo => (p.codigoBarras ?? '').isEmpty,
            })
          p,
    ];
  }

  void _elegirFiltro(_Filtro f, {int? proveedor}) => setState(() {
    _filtro = f;
    _proveedorId = proveedor;
  });

  void _salirDeSeleccion() {
    setState(() {
      _eligiendo = false;
      _marcados.clear();
    });
    _app?.ocultarBarra.value = false;
  }

  void _alternarMarca(int id) => setState(() => _marcados.contains(id) ? _marcados.remove(id) : _marcados.add(id));

  /// Escanear: si el código ya es de un producto se abre para editarlo; si no, se arma uno nuevo con ese código.
  Future<void> _escanear() async {
    final app = AppNs.of(context);
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    ProductoCompanion? existente;
    try {
      existente = await s.porCodigoBarras(codigo);
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
      return;
    }
    if (!mounted) return;
    final guardo = await mostrarFormularioProducto(context, cliente: s, usuarioId: u, proveedores: _proveedores, categorias: _categorias, producto: existente, codigoInicial: existente == null ? codigo : null);
    if (guardo) await _cargar();
  }

  Future<void> _nuevo() async {
    final app = AppNs.of(context);
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    final guardo = await mostrarFormularioProducto(context, cliente: s, usuarioId: u, proveedores: _proveedores, categorias: _categorias);
    if (guardo) await _cargar();
  }

  Future<void> _tocar(ProductoCompanion p) async {
    if (_eligiendo) return _alternarMarca(p.id);
    final app = AppNs.of(context);
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    final r = await mostrarHojaCambiarPrecio(context, servicio: s, usuarioId: u, producto: p, nombreProveedor: _nombreProveedor(p.proveedorId));
    if (!mounted) return;
    if (r == false) {
      final guardo = await mostrarFormularioProducto(context, cliente: s, usuarioId: u, proveedores: _proveedores, categorias: _categorias, producto: p);
      if (guardo) await _cargar();
    } else if (r == true) {
      await _cargar();
    }
  }

  /// Qué se puede hacer con lo elegido depende de desde dónde se eligió (mock `bulkCtx`).
  ContextoLote get _contextoLote => _filtro == _Filtro.proveedor
      ? ContextoLote.proveedor
      : _filtro == _Filtro.sinProveedor
      ? ContextoLote.asignarProveedor
      : _filtro == _Filtro.sinCategoria
      ? ContextoLote.asignarCategoria
      : ContextoLote.general;

  String get _etiquetaLote => switch (_contextoLote) {
    ContextoLote.proveedor => 'Editar (${_marcados.length})',
    ContextoLote.asignarProveedor => 'Asignar proveedor (${_marcados.length})',
    ContextoLote.asignarCategoria => 'Asignar categoría (${_marcados.length})',
    ContextoLote.general => 'Editar en lote',
  };

  Future<void> _editarEnLote() async {
    if (_marcados.isEmpty) {
      mostrarAvisoNs(context, 'Marcá al menos un producto');
      return;
    }
    final app = AppNs.of(context);
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    final elegidos = [for (final p in _todos) if (_marcados.contains(p.id)) p];
    final cambio = await mostrarHojaLote(context, servicio: s, usuarioId: u, productos: elegidos, proveedores: _proveedores, categorias: _categorias, contexto: _contextoLote, nombreProveedor: _nombreProveedor(_proveedorId));
    if (cambio && mounted) {
      _salirDeSeleccion();
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    return ValueListenableBuilder<bool>(
      valueListenable: app.productosEnConteo,
      builder: (context, conteo, _) => PantallaEntradaNs(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
                    child: ListenableBuilder(
                      listenable: app.pendientes,
                      builder: (context, _) => Row(
                        children: [
                          Expanded(child: Text(conteo ? 'Controlar stock' : 'Productos', style: tituloNs(conteo ? 34 : 42, track: conteo ? -0.05 : -0.055, color: ns.ink))),
                          BotonCircularNs(icono: IconoNs.campana, onTap: () => app.irA((_) => const PantallaNotificacionesNs()), etiqueta: app.pendientes.value.cantidad == 0 ? 'Notificaciones' : '${app.pendientes.value.cantidad} notificaciones', globo: app.pendientes.value.cantidad),
                          if (!conteo) ...[
                            const SizedBox(width: 12),
                            BotonNs(texto: '+ Nuevo', onTap: _nuevo, alto: 44, tamanio: 15, fondo: ns.prim, color: TokensNs.blanco, rellenar: false, paddingH: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: conteo
                        ? (_cargando
                              ? const Padding(padding: EdgeInsets.symmetric(horizontal: margenNs), child: EsqueletoListaNs())
                              : (_error != null ? EstadoErrorNs(texto: _error!, onReintentar: _cargar) : _vistaConteo(context, app)))
                        : _vistaCatalogo(context, app),
                  ),
                ],
              ),
              if (_eligiendo && !conteo) Positioned(left: 16, right: 16, bottom: 16, child: _BarraLote(cantidad: _marcados.length, etiqueta: _etiquetaLote, onEditar: _editarEnLote)),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────── Catálogo ─────────────

  Widget _vistaCatalogo(BuildContext context, ControladorAppNs app) {
    final ns = context.ns;
    final visibles = _visibles;
    return ListView(
      padding: EdgeInsets.only(bottom: _eligiendo ? 112 : BarraInferiorNs.espacioReservado - 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: margenNs),
          child: PresionNs(
            onTap: () => app.productosEnConteo.value = true,
            etiqueta: 'Controlar stock',
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
              decoration: BoxDecoration(color: ns.prim, borderRadius: BorderRadius.circular(999)),
              child: Row(
                children: [
                  Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0x24FFFFFF), shape: BoxShape.circle), alignment: Alignment.center, child: const IconoNsWidget(IconoNs.portapapeles, tamanio: 22, color: TokensNs.blanco)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Controlar stock', style: estiloNs(17, peso: FontWeight.w600, color: TokensNs.blanco)),
                        Text('Contá lo que hay en la góndola', style: estiloNs(14, color: const Color(0xBFFFFFFF))),
                      ],
                    ),
                  ),
                  const IconoNsWidget(IconoNs.chevron, tamanio: 18, color: TokensNs.blanco, grosor: 2.2),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: margenNs),
          child: Row(
            children: [
              Expanded(child: BuscadorNs(controller: _busqueda, placeholder: 'Buscar producto por nombre', onChanged: (_) => setState(() {}))),
              const SizedBox(width: 8),
              PresionNs(
                onTap: _escanear,
                etiqueta: 'Escanear código de barras',
                child: Container(width: 56, height: 56, decoration: BoxDecoration(color: ns.prim, shape: BoxShape.circle), alignment: Alignment.center, child: const IconoNsWidget(IconoNs.escanear, tamanio: 24, color: TokensNs.blanco)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_filtro == _Filtro.proveedor)
          _EncabezadoProveedor(nombre: _nombreProveedor(_proveedorId) ?? '', onTodos: () => _elegirFiltro(_Filtro.todos))
        else
          FilaChipsNs(
          chips: [
            ChipNs(texto: 'Todos', activo: _filtro == _Filtro.todos, onTap: () => _elegirFiltro(_Filtro.todos)),
            ChipNs(texto: 'Sin stock ($_nSinStock)', activo: _filtro == _Filtro.sinStock, onTap: () => _elegirFiltro(_Filtro.sinStock)),
            ChipNs(texto: 'Poco stock ($_nPocoStock)', activo: _filtro == _Filtro.pocoStock, onTap: () => _elegirFiltro(_Filtro.pocoStock)),
            for (final p in _proveedores) ChipNs(texto: p.nombre, activo: _filtro == _Filtro.proveedor && _proveedorId == p.id, onTap: () => _elegirFiltro(_Filtro.proveedor, proveedor: p.id)),
            ChipNs(texto: 'Sin proveedor', activo: _filtro == _Filtro.sinProveedor, onTap: () => _elegirFiltro(_Filtro.sinProveedor)),
            ChipNs(texto: 'Sin costo', activo: _filtro == _Filtro.sinCosto, onTap: () => _elegirFiltro(_Filtro.sinCosto)),
            ChipNs(texto: 'Sin categoría', activo: _filtro == _Filtro.sinCategoria, onTap: () => _elegirFiltro(_Filtro.sinCategoria)),
            ChipNs(texto: 'Sin código', activo: _filtro == _Filtro.sinCodigo, onTap: () => _elegirFiltro(_Filtro.sinCodigo)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(margenNs + 1, 8, margenNs + 4, 8),
          child: Row(
            children: [
              Expanded(child: Text(_eligiendo ? (_marcados.isEmpty ? 'Tocá los que quieras elegir' : '${_marcados.length} ${_marcados.length == 1 ? 'elegido' : 'elegidos'}') : 'Tocá uno para cambiar el precio', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute))),
              PresionNs(
                onTap: () {
                  if (_eligiendo) {
                    _salirDeSeleccion();
                  } else {
                    setState(() => _eligiendo = true);
                    app.ocultarBarra.value = true;
                  }
                },
                etiqueta: _eligiendo ? 'Cancelar' : 'Elegir varios',
                child: Container(height: 44, alignment: Alignment.center, child: Text(_eligiendo ? 'Cancelar' : 'Elegir varios', style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, decoracion: TextDecoration.underline))),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: margenNs),
          child: _cargando
              ? const EsqueletoListaNs()
              : _error != null
              ? EstadoErrorNs(texto: _error!, onReintentar: _cargar)
              : visibles.isEmpty
              ? Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text(_mensajeVacio, style: estiloNs(16, color: ns.mute)))
              : ListaAgrupadaNs(filas: [for (final p in visibles) _FilaProducto(producto: p, proveedor: _nombreProveedor(p.proveedorId), eligiendo: _eligiendo, marcado: _marcados.contains(p.id), onTap: () => _tocar(p))]),
        ),
      ],
    );
  }

  // ───────────── Controlar stock ─────────────

  Widget _vistaConteo(BuildContext context, ControladorAppNs app) {
    final ns = context.ns;
    final sin = _todos.where(sinStockNs).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BotonNs(texto: '‹ Volver a la lista', onTap: () => app.productosEnConteo.value = false, alto: 44, tamanio: 15, fondo: ns.s, color: ns.ink, rellenar: false, paddingH: 18),
        ),
        const SizedBox(height: 12),
        Text('Recorré la góndola y anotá lo que hay. Lo que dejes vacío se queda como está guardado.', style: estiloNs(15, altura: 1.4, color: ns.mute)),
        const SizedBox(height: 12),
        PresionNs(
          onTap: () async {
            await app.irA((_) => const PantallaConteoStock(soloSinStock: true));
            await _cargar(silencioso: true);
            await app.refrescar();
          },
          etiqueta: 'Productos sin stock',
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 22, 18),
            decoration: BoxDecoration(color: ns.wbg, borderRadius: BorderRadius.circular(32)),
            child: Row(
              children: [
                Container(width: 52, height: 52, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(IconoNs.alerta, tamanio: 24, color: ns.w)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Productos sin stock', style: estiloNs(20, peso: FontWeight.w600, track: -0.03, color: ns.w)),
                      Text('${sin.length} ${sin.length == 1 ? 'producto' : 'productos'} · todos los proveedores juntos', style: estiloNs(14, color: ns.w)),
                    ],
                  ),
                ),
                IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.w, grosor: 2.2),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SeccionNs('Contar por proveedor'),
        const SizedBox(height: 10),
        for (final prov in _proveedores) ...[
          Builder(
            builder: (context) {
              final delProv = _todos.where((p) => p.proveedorId == prov.id).toList();
              final nSin = delProv.where(sinStockNs).length;
              return TarjetaFilaNs(
                titulo: prov.nombre,
                subtitulo: '${delProv.length} ${delProv.length == 1 ? 'producto' : 'productos'} · $nSin sin stock',
                icono: IconoNs.producto,
                tamanioTitulo: 18,
                onTap: () async {
                  await app.irA((_) => PantallaConteoStock(proveedorId: prov.id));
                  await _cargar(silencioso: true);
                  await app.refrescar();
                },
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Ganancia sobre el precio, redondeada: 2.100 con costo 1.470 → 30. Null si falta el costo o el precio.
int? _ganancia(ProductoCompanion p) {
  final precio = p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos;
  final costo = p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos;
  if (precio == null || costo == null || precio <= 0 || costo <= 0) return null;
  return ((precio - costo) * 100 / precio).round();
}

/// Encabezado de "los productos de un proveedor": iniciales, nombre y "Todos" para volver.
class _EncabezadoProveedor extends StatelessWidget {
  const _EncabezadoProveedor({required this.nombre, required this.onTodos});
  final String nombre;
  final VoidCallback onTodos;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final iniciales = nombre.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: margenNs),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.ibg, shape: BoxShape.circle), alignment: Alignment.center, child: Text(iniciales, style: estiloNs(16, peso: FontWeight.w700, color: ns.i))),
          const SizedBox(width: 12),
          Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(22, peso: FontWeight.w500, track: -0.03, color: ns.ink))),
          PresionNs(
            onTap: onTodos,
            etiqueta: 'Todos',
            child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center, child: Text('Todos', style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, decoracion: TextDecoration.underline))),
          ),
        ],
      ),
    );
  }
}

class _FilaProducto extends StatelessWidget {
  const _FilaProducto({required this.producto, required this.proveedor, required this.eligiendo, required this.marcado, required this.onTap});
  final ProductoCompanion producto;
  final String? proveedor;
  final bool eligiendo;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final p = producto;
    final sin = sinStockNs(p);
    final poco = pocoStockNs(p);
    return PresionNs(
      onTap: onTap,
      etiqueta: p.nombre,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        color: marcado ? ns.ibg : ns.s,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (eligiendo) ...[CasillaNs(marcada: marcado), const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text('${proveedor ?? 'Sin proveedor'} · ${sin ? '0' : stockTextoNs(p)}', style: estiloNs(14, color: ns.mute, tabular: true)),
                      if (sin) const EtiquetaStockNs('Sin stock', sinStock: true) else if (poco) const EtiquetaStockNs('Poco stock', sinStock: false),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(precioTextoNs(p), style: estiloNs(21, peso: peso450, track: -0.04, color: ns.ink, tabular: true)),
                if (_ganancia(p) != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: ns.gbg, borderRadius: BorderRadius.circular(999)),
                    child: Text('${_ganancia(p)}% gan.', style: estiloNs(12, peso: FontWeight.w700, color: ns.g, tabular: true)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra de lote flotante (docs/03 B3.1): "N seleccionados" y "Editar en lote".
class _BarraLote extends StatelessWidget {
  const _BarraLote({required this.cantidad, required this.etiqueta, required this.onEditar});
  final int cantidad;
  final String etiqueta;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return EntradaNs(
      duracion: const Duration(milliseconds: 450),
      child: Container(
        height: 68,
        padding: const EdgeInsets.fromLTRB(26, 0, 10, 0),
        decoration: BoxDecoration(color: ns.toast, borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Color(0x47121317), blurRadius: 40, offset: Offset(0, 18))]),
        child: Row(
          children: [
            Expanded(child: Text(cantidad == 1 ? '1 seleccionado' : '$cantidad seleccionados', style: estiloNs(16, peso: FontWeight.w600, color: TokensNs.blanco))),
            BotonNs(texto: etiqueta, onTap: onEditar, alto: 48, tamanio: 15, fondo: cantidad == 0 ? const Color(0x29FFFFFF) : ns.paper, color: cantidad == 0 ? const Color(0xB3FFFFFF) : ns.ink, rellenar: false, paddingH: 22),
          ],
        ),
      ),
    );
  }
}
