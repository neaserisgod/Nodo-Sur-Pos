// Estado de la pantalla Proveedores (fase 13 — reemplaza a Reposición, y
// absorbe Productos y Stock por proveedor). Tres vistas posibles en
// `ListaMaestra`: "Todos" el catálogo entero, "Sin proveedor" los productos
// huérfanos, o un proveedor puntual — mismo controlador para las tres, igual
// que nivel 1 y nivel 2 ya vivían juntos acá.

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_arqueo_intermedio.dart'
    show lataEsperadaIntermedia;
import '../../data/repositorio_cierre.dart'
    show precioListaCigarrillosDelDia, sesionCerradaAnterior;
import '../../data/repositorio_configuracion.dart';
import '../../data/repositorio_deuda_proveedores.dart' show saldosDeuda;
import '../../data/repositorio_productos.dart'
    as repo_productos
    show
        CambioDePrecioPropuesto,
        aplicarPorcentajeDeProveedor,
        cambiosPorPorcentaje,
        guardarPorcentajeProveedor;
import '../../data/repositorio_productos.dart'
    show
        ajustarMontoEnLote,
        asignarCategoriaEnLote,
        asignarProveedorEnLote,
        cambiarActivoEnLote,
        crearCategoria,
        listarCategorias;
import '../../data/repositorio_proveedores.dart';
import '../../data/repositorio_reposicion.dart';
import '../../domain/edicion_masiva_precios.dart';
import '../../domain/periodo.dart';
import '../../domain/tablero.dart' show avisaPorStock;
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;

enum SeleccionProveedor { todos, sinProveedor, proveedor }

class ProveedoresControlador extends ChangeNotifier {
  ProveedoresControlador(
    this.db, {
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;

  /// Null si no hay sesión de caja abierta: pagar en efectivo/Mercado Pago
  /// queda deshabilitado en ese caso (no hay dónde grabar el movimiento),
  /// mismo criterio que ya tenía Reposición.
  final int? sesionCajaId;

  bool cargando = true;

  /// Lo que se le debe a cada proveedor (cuenta corriente, 2026-09-29). Solo
  /// aparecen los que alguna vez tuvieron un movimiento.
  Map<int, int> deudaPorProveedor = {};

  int deudaDe(int proveedorId) => deudaPorProveedor[proveedorId] ?? 0;

  PeriodoResumen periodo = PeriodoResumen.mes;
  List<ResumenProveedorNivel1> resumenes = [];
  List<Categoria> categorias = [];

  SeleccionProveedor vista = SeleccionProveedor.todos;

  /// "Lenguaje de diseño" (Bruno, 2026-09-26, mock `Proveedores.dc.html`):
  /// la lista de proveedores vuelve a estar siempre a la izquierda y el
  /// detalle a la derecha, así que ya no hay "picker" y "detalle" como dos
  /// sub-pantallas (séptima pasada del 2026-09-25) — se elige y se ve en
  /// la misma pantalla.

  /// Todos los productos activos: para contar, por proveedor, cuántos hay y
  /// cuántos avisan por stock (la lista de la izquierda).
  List<ProductoDeProveedor> todosLosProductos = [];

  /// Unidades/gramos vendidos por producto en el período elegido, y en los
  /// últimos 30 días (el "vendido hace poco" de `avisaPorStock`).
  Map<int, int> vendidoEnPeriodo = {};
  Map<int, int> vendidoUltimos30 = {};

  /// Filtro "Stock bajo" de la grilla de productos.
  bool soloStockBajo = false;

  void cambiarSoloStockBajo(bool valor) {
    soloStockBajo = valor;
    notifyListeners();
  }

  bool avisaStock(ProductoDeProveedor p) => avisaPorStock(
    stock: p.stock,
    minimo: p.stockMinimo,
    vendidoHacePoco: (vendidoUltimos30[p.id] ?? 0) > 0,
  );

  /// Buscador de arriba (contextual, 2026-09-28): filtra los productos de la
  /// vista elegida y la lista de proveedores. Vacío = sin filtro.
  String busqueda = '';

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  bool coincideProducto(ProductoDeProveedor p) =>
      coincideBusqueda(p.nombre, busqueda) ||
      (p.codigoBarras != null && p.codigoBarras!.contains(busqueda));

  /// Un proveedor se muestra en la lista si su nombre coincide o si tiene
  /// algún producto que coincide (así se ve de quién es lo que se busca).
  bool proveedorVisible(Proveedor p) =>
      busqueda.isEmpty ||
      coincideBusqueda(p.nombre, busqueda) ||
      todosLosProductos.any(
        (prod) => prod.proveedorId == p.id && coincideProducto(prod),
      );

  bool get sinProveedorVisible =>
      busqueda.isEmpty ||
      todosLosProductos.any(
        (prod) => prod.proveedorId == null && coincideProducto(prod),
      );

  List<ProductoDeProveedor> get productosVisibles => [
    for (final p in productos)
      if ((!soloStockBajo || avisaStock(p)) &&
          (busqueda.isEmpty || coincideProducto(p)))
        p,
  ];

  int cantidadDeProductos(int? proveedorId) =>
      todosLosProductos.where((p) => p.proveedorId == proveedorId).length;

  int stockBajoDe(int? proveedorId) => todosLosProductos
      .where((p) => p.proveedorId == proveedorId && avisaStock(p))
      .length;

  int get stockBajoTotal => todosLosProductos.where(avisaStock).length;

  Proveedor? seleccionado;
  ResumenReposicionProveedor? detalleSeleccionado;
  ResumenAgregadoProductos? agregadoTodos;
  ResumenAgregadoProductos? agregadoSinProveedor;

  /// Productos de la vista activa (segunda corrección post-revisión) —
  /// nombre, costo, precio y margen, la tabla del panel derecho.
  List<ProductoDeProveedor> productos = [];

  /// Edición masiva de precios (Bruno, 2026-09-16: "subir el precio de 3
  /// productos... a la vez"). Un `Set` de ids en vez de un booleano por fila:
  /// "modo selección" está activo mientras haya al menos uno marcado, sin un
  /// flag aparte que se pueda desincronizar de la selección real. Se limpia
  /// sola al cambiar de vista (`seleccionar*`) — una selección de la vista
  /// anterior no tiene sentido en la nueva.
  Set<int> seleccionMasiva = {};

  bool get enModoSeleccionMasiva => seleccionMasiva.isNotEmpty;

  void alternarSeleccionMasiva(int productoId) {
    if (!seleccionMasiva.add(productoId)) seleccionMasiva.remove(productoId);
    notifyListeners();
  }

  void limpiarSeleccionMasiva() {
    seleccionMasiva.clear();
    notifyListeners();
  }

  /// Proveedores activos para el selector de "reasignar proveedor" de la
  /// edición masiva — mismo listado que ya arma la lista maestra, sin
  /// volver a consultar la base.
  List<Proveedor> get proveedoresDisponibles =>
      resumenes.map((r) => r.proveedor).toList();

  /// Ajusta precio o costo de todos los productos marcados ("maximizar el
  /// ajuste masivo", Bruno 2026-09-16) — mismo camino de escritura que
  /// editar uno por uno (`ajustarMontoEnLote` reusa `actualizarProducto`
  /// producto por producto, Regla 3), así que el historial de precios
  /// queda idéntico.
  Future<void> aplicarAjusteMontoMasivo({
    required CampoMonto campo,
    required TipoAjustePrecio tipo,
    required int valor,
  }) async {
    if (seleccionMasiva.isEmpty) return;
    await ajustarMontoEnLote(
      db,
      productoIds: seleccionMasiva.toList(),
      campo: campo,
      tipo: tipo,
      valor: valor,
      usuarioId: usuarioId,
    );
    seleccionMasiva.clear();
    await cargarTodo();
  }

  Future<void> aplicarCategoriaMasiva(int? categoriaId) async {
    if (seleccionMasiva.isEmpty) return;
    await asignarCategoriaEnLote(
      db,
      productoIds: seleccionMasiva.toList(),
      categoriaId: categoriaId,
      usuarioId: usuarioId,
    );
    seleccionMasiva.clear();
    await cargarTodo();
  }

  Future<void> aplicarProveedorMasivo(int? proveedorId) async {
    if (seleccionMasiva.isEmpty) return;
    await asignarProveedorEnLote(
      db,
      productoIds: seleccionMasiva.toList(),
      proveedorId: proveedorId,
      usuarioId: usuarioId,
    );
    seleccionMasiva.clear();
    await cargarTodo();
  }

  Future<void> aplicarActivoMasivo(bool activo) async {
    if (seleccionMasiva.isEmpty) return;
    await cambiarActivoEnLote(
      db,
      productoIds: seleccionMasiva.toList(),
      activo: activo,
    );
    seleccionMasiva.clear();
    await cargarTodo();
  }

  Future<void> cargarTodo() async {
    final config = await db.select(db.configuracionTabla).getSingle();
    periodo = PeriodoResumen.values.byName(config.periodoResumen);
    categorias = await listarCategorias(db);
    deudaPorProveedor = await saldosDeuda(db);
    await _recargarResumenes();

    switch (vista) {
      case SeleccionProveedor.todos:
        await seleccionarTodos();
      case SeleccionProveedor.sinProveedor:
        await seleccionarSinProveedor();
      case SeleccionProveedor.proveedor:
        // El proveedor elegido puede haber cambiado de fila (separar/pagar
        // recalcula todo), o haberse desactivado — se refresca su detalle en
        // vez de perder la selección cada vez que algo se guarda.
        final actual = seleccionado;
        final sigueActivo =
            actual != null && resumenes.any((r) => r.proveedor.id == actual.id);
        if (sigueActivo) {
          await seleccionar(actual.id);
        } else {
          await seleccionarTodos();
        }
    }

    cargando = false;
    notifyListeners();
  }

  Future<void> _recargarResumenes() async {
    final ahora = DateTime.now();
    todosLosProductos = await productosTodos(db);
    vendidoEnPeriodo = await vendidoPorProductoDesde(
      db,
      inicioDePeriodo(
            periodo,
            ahora,
            ultimoPago: seleccionado?.ultimoPagoFecha,
          ) ??
          DateTime(2000),
    );
    vendidoUltimos30 = await vendidoPorProductoDesde(
      db,
      DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
      ).subtract(const Duration(days: 30)),
    );
    resumenes = await resumenProveedoresNivel1(
      db,
      periodo: periodo,
      ahora: DateTime.now(),
    );
    agregadoTodos = await resumenTodosLosProductos(
      db,
      periodo: periodo,
      ahora: DateTime.now(),
    );
    agregadoSinProveedor = await resumenProductosSinProveedor(
      db,
      periodo: periodo,
      ahora: DateTime.now(),
    );
  }

  Future<void> cambiarPeriodo(PeriodoResumen nuevo) async {
    periodo = nuevo;
    await configurarPeriodoResumen(db, nuevo.name);
    await _recargarResumenes();
    notifyListeners();
  }

  Future<void> seleccionarTodos() async {
    vista = SeleccionProveedor.todos;
    seleccionado = null;
    detalleSeleccionado = null;
    seleccionMasiva.clear();
    soloStockBajo = false;
    productos = await productosTodos(db);
    notifyListeners();
  }

  Future<void> seleccionarSinProveedor() async {
    vista = SeleccionProveedor.sinProveedor;
    seleccionado = null;
    detalleSeleccionado = null;
    seleccionMasiva.clear();
    soloStockBajo = false;
    productos = await productosSinProveedor(db);
    notifyListeners();
  }

  Future<void> seleccionar(int proveedorId) async {
    vista = SeleccionProveedor.proveedor;
    final resumen = resumenes.firstWhere((r) => r.proveedor.id == proveedorId);
    seleccionado = resumen.proveedor;
    detalleSeleccionado = await resumenReposicionDeProveedor(
      db,
      resumen.proveedor,
    );
    seleccionMasiva.clear();
    soloStockBajo = false;
    productos = await productosDeProveedor(db, proveedorId);
    notifyListeners();
  }

  /// Cifras del proveedor elegido para el resumen de arriba (segunda
  /// corrección post-revisión) — mezcla el nivel 1 (stock/costo/venta/
  /// ganancia, ya calculado para toda la lista) con `separadoCentavos`
  /// (nivel 2), sin recalcular nada de nuevo.
  ResumenProveedorNivel1? get resumenNivel1DelSeleccionado {
    final id = seleccionado?.id;
    if (id == null) return null;
    return resumenes.firstWhere((r) => r.proveedor.id == id);
  }

  /// Título del panel derecho, para las tres vistas.
  String get tituloSeleccion => switch (vista) {
    SeleccionProveedor.todos => 'Todos',
    SeleccionProveedor.sinProveedor => 'Sin proveedor',
    SeleccionProveedor.proveedor => seleccionado?.nombre ?? '',
  };

  /// Las cinco cifras de `FilaMetricas`, unificadas para las tres vistas —
  /// `separado` es null en "Todos"/"Sin proveedor" (no hay reposición sin un
  /// proveedor real). Null completo si todavía no cargó nada.
  ({int stock, int costo, int venta, int ganancia, int? separado})? get cifras {
    switch (vista) {
      case SeleccionProveedor.todos:
        final a = agregadoTodos;
        if (a == null) return null;
        return (
          stock: a.stockValorizadoCentavos,
          costo: a.costoValorizadoCentavos,
          venta: a.vendidoCentavos,
          ganancia: a.gananciaBrutaCentavos,
          separado: null,
        );
      case SeleccionProveedor.sinProveedor:
        final a = agregadoSinProveedor;
        if (a == null) return null;
        return (
          stock: a.stockValorizadoCentavos,
          costo: a.costoValorizadoCentavos,
          venta: a.vendidoCentavos,
          ganancia: a.gananciaBrutaCentavos,
          separado: null,
        );
      case SeleccionProveedor.proveedor:
        final r = resumenNivel1DelSeleccionado;
        if (r == null) return null;
        return (
          stock: r.stockValorizadoCentavos,
          costo: r.costoValorizadoCentavos,
          venta: r.vendidoCentavos,
          ganancia: r.gananciaBrutaCentavos,
          separado: detalleSeleccionado?.separadoCentavos ?? 0,
        );
    }
  }

  /// Separar/pagar/"Avanzado" solo tienen sentido con un proveedor real
  /// elegido — no hay reposición ni cuenta corriente para "Todos" o "Sin
  /// proveedor".
  bool get esProveedorReal =>
      vista == SeleccionProveedor.proveedor && seleccionado != null;

  /// Serra Cigarros no se repone por el camino genérico (Regla 6: la lata ya
  /// reserva su costo aparte, `calcularReposicion` excluye sus líneas) —
  /// separar/pagar ahí quedaban siempre en $0. Por eso tiene su propio
  /// panel ("Ver lata") en vez de "Avanzado".
  bool get esSerraCigarros => esProveedorReal && seleccionado!.cajaAparte;

  /// Los números del panel "Ver lata" — null sin sesión abierta (no hay
  /// "hoy" que mostrar).
  Future<
    ({
      int saldoLataCentavos,
      int vendidoHoyCentavos,
      int pendienteArrastradoCentavos,
    })?
  >
  datosLata() async {
    final sesion = sesionCajaId;
    if (sesion == null) return null;
    final anterior = await sesionCerradaAnterior(db, sesion);
    return (
      saldoLataCentavos: await lataEsperadaIntermedia(db, sesion),
      vendidoHoyCentavos: await precioListaCigarrillosDelDia(db, sesion),
      pendienteArrastradoCentavos: anterior?.lataPendienteCentavos ?? 0,
    );
  }

  Future<void> separar() async {
    final proveedor = seleccionado;
    if (proveedor == null) return;
    await separarProveedor(db, proveedorId: proveedor.id);
    await cargarTodo();
  }

  /// No valida el monto contra lo separado acá: el diálogo ya tiene el
  /// resumen en memoria y valida antes de llamar a esto (mismo criterio que
  /// tenía Reposición).
  /// [montoMpCentavos]: la parte de [montoCentavos] que sale de Mercado
  /// Pago (ver `pagarProveedor`).
  Future<void> pagar({
    required int montoCentavos,
    required int montoMpCentavos,
  }) async {
    final proveedor = seleccionado;
    final sesion = sesionCajaId;
    if (proveedor == null || sesion == null) return;
    await pagarProveedor(
      db,
      proveedorId: proveedor.id,
      sesionCajaId: sesion,
      usuarioId: usuarioId,
      montoCentavos: montoCentavos,
      montoMpCentavos: montoMpCentavos,
    );
    await cargarTodo();
  }

  /// Nivel 2 pasó a ser puramente informativo (segunda corrección
  /// post-revisión): medio de pago se guarda desde acá, junto con el resto
  /// de "Avanzado". [colchonCentavos] ya NO se edita a mano (Regla 13: es
  /// ganancia retenida real, crece solo con `retenerGanancia` al revisar el
  /// cierre) — se mantiene opcional para no tocarlo si nadie lo pasa.
  Future<void> guardarAvanzado({
    String? nombre,
    required String codigo,
    String? diaPedido,
    String? diaEntrega,
    required bool activo,
    required String medioPago,
    bool? cajaAparte,
    int? colchonCentavos,
  }) async {
    final proveedor = seleccionado;
    if (proveedor == null) return;
    await actualizarProveedorAvanzado(
      db,
      proveedorId: proveedor.id,
      nombre: nombre,
      codigo: codigo,
      diaPedido: diaPedido,
      diaEntrega: diaEntrega,
      activo: activo,
      medioPago: medioPago,
      cajaAparte: cajaAparte,
      colchonReposicionCentavos: colchonCentavos,
    );
    await cargarTodo();
  }

  /// Alta de un proveedor nuevo (Bruno, 2026-09-05: "se debe poder editar y
  /// agregar los proveedores"). Recarga y selecciona el nuevo directo —
  /// mismo criterio que "+ Nuevo producto" en la vista actual: verlo elegido
  /// confirma que entró, sin tener que buscarlo en la lista.
  Future<void> crearProveedorNuevo({
    required String nombre,
    required String codigo,
    String? diaPedido,
    String? diaEntrega,
    String medioPago = 'Efectivo',
  }) async {
    final id = await crearProveedor(
      db,
      nombre: nombre,
      codigo: codigo,
      diaPedido: diaPedido,
      diaEntrega: diaEntrega,
      medioPago: medioPago,
    );
    await cargarTodo();
    await seleccionar(id);
  }

  /// Refresca solo la vista activa después de crear/editar un producto desde
  /// el `Modal` de edición — no hace falta recargar todo el árbol de
  /// proveedores para que un cambio de nombre/precio se vea reflejado.
  Future<void> recargarSeleccionActual() => cargarTodo();

  // ─── Porcentaje de ganancia del proveedor (2026-09-29) ───────────────

  /// Guarda el porcentaje (null = sin porcentaje). No cambia ningún precio.
  Future<void> guardarPorcentaje(int? markupBp) async {
    await repo_productos.guardarPorcentajeProveedor(
      db,
      proveedorId: seleccionado!.id,
      markupBp: markupBp,
    );
    await cargarTodo();
  }

  /// Qué precios cambiarían al aplicar el porcentaje del proveedor elegido.
  Future<List<repo_productos.CambioDePrecioPropuesto>> cambiosPropuestos() =>
      repo_productos.cambiosPorPorcentaje(db, seleccionado!.id);

  /// Recalcula los precios del proveedor elegido; devuelve cuántos cambiaron.
  Future<int> aplicarPorcentaje() async {
    final n = await repo_productos.aplicarPorcentajeDeProveedor(
      db,
      proveedorId: seleccionado!.id,
      usuarioId: usuarioId,
    );
    await cargarTodo();
    return n;
  }

  Future<int> agregarCategoria(String nombre) async {
    final id = await crearCategoria(db, nombre);
    categorias = await listarCategorias(db);
    notifyListeners();
    return id;
  }
}
