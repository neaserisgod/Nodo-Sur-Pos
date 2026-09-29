// Carga histórica producto por producto (reemplaza a la de planilla, fase
// 9): mismo carrito que la venta en vivo — buscar, agregar, ajustar
// cantidad — pero para una fecha elegida una sola vez al entrar, y con los
// medios de pago como mocks (solo etiquetan el pago, nunca llaman a la
// terminal Point). Nada se graba hasta `guardarDia()`
// (`repositorio_carga_historica.dart`).
//
// Deliberadamente más simple que `VentaControlador`: sin atajos de teclado,
// sin alta rápida (se asume que el producto ya existe en el catálogo al
// reconstruir histórico), sin descuento — es una herramienta de carga de
// datos, no el mostrador. Ver CLAUDE.md, "no diseñar para hipotéticos".

import 'package:flutter/widgets.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../data/repositorio_carga_historica.dart';
import '../../data/repositorio_configuracion.dart';
import '../../data/repositorio_historial.dart';
import '../../data/repositorio_ventas.dart';
import '../../domain/medio_pago.dart';
import '../../domain/recargo_cigarrillos.dart';
import '../../domain/venta.dart';

/// Una venta ya "agregada" a la tanda del día, solo para mostrarla en la
/// lista de resumen — lo que de verdad se guarda es `_pendientes` (con el
/// carrito y los pagos completos).
class VentaHistoricaResumen {
  final String descripcion;
  final int totalCentavos;

  const VentaHistoricaResumen({
    required this.descripcion,
    required this.totalCentavos,
  });
}

class CargaHistoricaControlador extends ChangeNotifier {
  CargaHistoricaControlador(this.db, {required this.usuarioId}) {
    campoTexto.addListener(_alCambiarTexto);
  }

  final AppDatabase db;
  final int usuarioId;

  final TextEditingController campoTexto = TextEditingController();
  final FocusNode focoCampoPrincipal = FocusNode();

  List<Producto> _catalogo = [];
  ConfiguracionNegocio? configuracion;
  MedioDePago? medioEfectivo;
  MedioDePago? medioVirtual;
  bool cargando = true;
  String? error;

  /// Aviso corto (Regla 7: un pesable sin gramos o sin precio por kilo es un
  /// error, no un cero silencioso), mismo criterio que la venta en vivo.
  String? avisoBusqueda;

  List<Producto> coincidencias = [];

  /// Recordatorio (Regla 6, arrastre de pendiente de cigarrillos entre días
  /// por orden de inserción): igual que la carga de planilla vieja, cargar
  /// fuera de orden cronológico lo rompe.
  DateTime? ultimoDiaCargado;

  /// Días que ya tienen una caja cerrada (del mostrador o cargada acá) —
  /// el calendario los pinta como "Cargado".
  Set<DateTime> diasConCaja = {};

  /// Fecha del día que se está cargando — se elige una sola vez, antes de
  /// poder tocar el carrito.
  DateTime? fecha;

  List<LineaVenta> carrito = [];
  ComposicionPago? medioElegido;
  int? montoEfectivoMixtoCentavos;

  /// Ventas ya "agregadas" a la tanda de este día, sin persistir todavía.
  final List<VentaHistoricaPendiente> _pendientes = [];
  final List<VentaHistoricaResumen> ventasCargadas = [];

  int get totalTandaCentavos =>
      ventasCargadas.fold<int>(0, (a, v) => a + v.totalCentavos);

  bool get hayTexto => campoTexto.text.trim().isNotEmpty;

  bool get mostrarSinCoincidencias => hayTexto && coincidencias.isEmpty;

  int get subtotalCentavos => Venta(lineas: carrito).subtotalCentavos;

  ResultadoTotalVenta? get resultado =>
      medioElegido == null ? null : _calcularCon(medioElegido!);

  ResultadoTotalVenta _calcularCon(ComposicionPago medio) {
    final config = configuracion!;
    return calcularTotalVenta(
      venta: Venta(lineas: carrito),
      composicionPago: medio,
      configRecargoCigarrillos: ConfigRecargoCigarrillos(
        primerAtadoCentavos: config.recargoPrimerAtadoCentavos,
        atadoAdicionalCentavos: config.recargoAtadoAdicionalCentavos,
        cigarroSueltoCentavos: config.recargoSueltoCentavos,
      ),
      pasoRedondeoCentavos: config.pasoRedondeoCentavos,
    );
  }

  Future<void> cargarTodo() async {
    _catalogo = await db.select(db.productos).get();
    configuracion = await configuracionNegocioActual(db);
    medioEfectivo = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(true))).getSingle();
    medioVirtual = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(false))).getSingle();
    final dias = await listarDias(db);
    ultimoDiaCargado = dias.isEmpty ? null : dias.first.sesion.fechaApertura;
    diasConCaja = {for (final d in dias) DateTime(d.sesion.fechaApertura.year, d.sesion.fechaApertura.month, d.sesion.fechaApertura.day)};
    cargando = false;
    notifyListeners();
  }

  // ─── Fecha ────────────────────────────────────────────────────────────

  void elegirFecha(DateTime nueva) {
    fecha = nueva;
    error = null;
    notifyListeners();
  }

  // ─── Campo único / carrito ───────────────────────────────────────────

  void _alCambiarTexto() {
    coincidencias = buscarProductos(
      catalogo: _catalogo,
      textoBuscado: campoTexto.text,
      exigirStock: false,
    );
    avisoBusqueda = null;
    notifyListeners();
  }

  Producto? productoPorId(String productoId) {
    final id = int.tryParse(productoId);
    if (id == null) return null;
    for (final p in _catalogo) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// [montoVariosCentavos] obligatorio (e ignorado para cualquier otro
  /// producto) cuando `producto.esVarios` — mismo criterio que la venta en
  /// vivo.
  void agregarProducto(Producto producto, {int? montoVariosCentavos}) {
    final consulta = interpretarTexto(campoTexto.text);

    if (producto.esPesable) {
      if (consulta.gramos == null || consulta.gramos! <= 0) {
        avisoBusqueda =
            'Escribí los gramos antes del nombre, por ejemplo "200 ${producto.nombre}"';
        notifyListeners();
        return;
      }
      if (producto.precioPorKiloCentavos == null) {
        avisoBusqueda =
            '${producto.nombre} no tiene precio por kilo cargado (Regla 7) — cargalo en Productos antes de cargarlo acá.';
        notifyListeners();
        return;
      }
    }

    final linea = lineaDesdeProducto(
      producto,
      cantidad: consulta.gramos == null ? 1 : null,
      gramos: consulta.gramos,
      montoVariosCentavos: montoVariosCentavos,
    );
    avisoBusqueda = null;
    if (!linea.esVarios) {
      final indiceExistente = carrito.indexWhere(
        (l) => l.productoId == linea.productoId,
      );
      if (indiceExistente != -1) {
        carrito = List.of(carrito);
        carrito[indiceExistente] = _sumarLineas(
          carrito[indiceExistente],
          linea,
        );
        campoTexto.clear();
        notifyListeners();
        return;
      }
    }
    carrito = [...carrito, linea];
    campoTexto.clear();
    notifyListeners();
  }

  LineaVenta _sumarLineas(LineaVenta actual, LineaVenta nueva) {
    if (actual is LineaVentaPorUnidad && nueva is LineaVentaPorUnidad) {
      return LineaVentaPorUnidad(
        productoId: actual.productoId,
        nombreProducto: actual.nombreProducto,
        proveedorId: actual.proveedorId,
        cantidad: actual.cantidad + nueva.cantidad,
        esVarios: actual.esVarios,
        tipoCigarrillo: actual.tipoCigarrillo,
        precioUnitarioCentavos: actual.precioUnitarioCentavos,
        costoUnitarioCentavos: actual.costoUnitarioCentavos,
      );
    }
    if (actual is LineaVentaPesable && nueva is LineaVentaPesable) {
      return LineaVentaPesable(
        productoId: actual.productoId,
        nombreProducto: actual.nombreProducto,
        proveedorId: actual.proveedorId,
        gramos: actual.gramos + nueva.gramos,
        precioPorKiloCentavos: actual.precioPorKiloCentavos,
        costoPorKiloCentavos: actual.costoPorKiloCentavos,
      );
    }
    throw StateError('Línea pesable y por unidad con el mismo productoId');
  }

  void eliminarLinea(int index) {
    if (index < 0 || index >= carrito.length) return;
    carrito = [...carrito]..removeAt(index);
    notifyListeners();
  }

  void ajustarCantidad(int index, int delta) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPorUnidad) return;
    final nuevaCantidad = linea.cantidad + delta;
    if (nuevaCantidad <= 0) {
      eliminarLinea(index);
      return;
    }
    carrito = [...carrito];
    carrito[index] = LineaVentaPorUnidad(
      productoId: linea.productoId,
      nombreProducto: linea.nombreProducto,
      proveedorId: linea.proveedorId,
      cantidad: nuevaCantidad,
      esVarios: linea.esVarios,
      tipoCigarrillo: linea.tipoCigarrillo,
      precioUnitarioCentavos: linea.precioUnitarioCentavos,
      costoUnitarioCentavos: linea.costoUnitarioCentavos,
    );
    notifyListeners();
  }

  void editarCantidadExacta(int index, int nuevaCantidad) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPorUnidad) return;
    if (nuevaCantidad <= 0) {
      eliminarLinea(index);
      return;
    }
    carrito = [...carrito];
    carrito[index] = LineaVentaPorUnidad(
      productoId: linea.productoId,
      nombreProducto: linea.nombreProducto,
      proveedorId: linea.proveedorId,
      cantidad: nuevaCantidad,
      esVarios: linea.esVarios,
      tipoCigarrillo: linea.tipoCigarrillo,
      precioUnitarioCentavos: linea.precioUnitarioCentavos,
      costoUnitarioCentavos: linea.costoUnitarioCentavos,
    );
    notifyListeners();
  }

  void editarGramosExacto(int index, int nuevosGramos) {
    if (index < 0 || index >= carrito.length) return;
    final linea = carrito[index];
    if (linea is! LineaVentaPesable) return;
    if (nuevosGramos <= 0) {
      eliminarLinea(index);
      return;
    }
    carrito = [...carrito];
    carrito[index] = LineaVentaPesable(
      productoId: linea.productoId,
      nombreProducto: linea.nombreProducto,
      proveedorId: linea.proveedorId,
      gramos: nuevosGramos,
      precioPorKiloCentavos: linea.precioPorKiloCentavos,
      costoPorKiloCentavos: linea.costoPorKiloCentavos,
    );
    notifyListeners();
  }

  void cancelarVentaActual() {
    carrito = [];
    medioElegido = null;
    montoEfectivoMixtoCentavos = null;
    campoTexto.clear();
    notifyListeners();
  }

  // ─── Medio de pago (mock: solo etiqueta, nunca llama a Point) ────────

  void elegirMedio(ComposicionPago medio) {
    medioElegido = medio;
    if (medio != ComposicionPago.mixto) montoEfectivoMixtoCentavos = null;
    notifyListeners();
  }

  void confirmarMixto(int montoEfectivoCentavos) {
    final totalMixto = _calcularCon(ComposicionPago.mixto).totalCentavos;
    medioElegido = clasificarComposicion(
      montoEfectivoCentavos: montoEfectivoCentavos,
      totalCentavos: totalMixto,
    );
    montoEfectivoMixtoCentavos =
        medioElegido == ComposicionPago.mixto ? montoEfectivoCentavos : null;
    notifyListeners();
  }

  List<PagoARegistrar>? _construirPagos() {
    final medio = medioElegido;
    final total = resultado?.totalCentavos;
    if (medio == null || total == null) return null;

    return switch (medio) {
      ComposicionPago.efectivo => [
        PagoARegistrar(
          medioPagoId: medioEfectivo!.id,
          montoCentavos: total,
          esEfectivo: true,
        ),
      ],
      ComposicionPago.virtual => [
        PagoARegistrar(
          medioPagoId: medioVirtual!.id,
          montoCentavos: total,
          esEfectivo: false,
        ),
      ],
      ComposicionPago.mixto =>
        montoEfectivoMixtoCentavos == null
            ? null
            : [
                PagoARegistrar(
                  medioPagoId: medioEfectivo!.id,
                  montoCentavos: montoEfectivoMixtoCentavos!,
                  esEfectivo: true,
                ),
                PagoARegistrar(
                  medioPagoId: medioVirtual!.id,
                  montoCentavos: total - montoEfectivoMixtoCentavos!,
                  esEfectivo: false,
                ),
              ],
    };
  }

  // ─── Agregar venta a la tanda del día (mock de "cobrar") ─────────────

  /// Suma la venta actual a la tanda del día — no toca la base, solo la
  /// lista en memoria. Devuelve `false` (y deja `error` seteado) si falta
  /// carrito o medio de pago.
  bool agregarVentaALaTanda() {
    if (carrito.isEmpty) {
      error = 'El carrito está vacío';
      notifyListeners();
      return false;
    }
    final pagos = _construirPagos();
    if (pagos == null) {
      error = 'Elegí un medio de pago';
      notifyListeners();
      return false;
    }

    final ventaActual = Venta(lineas: carrito);
    _pendientes.add(
      VentaHistoricaPendiente(
        venta: ventaActual,
        resultado: resultado!,
        pagos: pagos,
      ),
    );
    ventasCargadas.add(
      VentaHistoricaResumen(
        descripcion: carrito.length == 1
            ? carrito.first.nombreProducto
            : '${carrito.first.nombreProducto} y ${carrito.length - 1} más',
        totalCentavos: resultado!.totalCentavos,
      ),
    );
    error = null;
    cancelarVentaActual();
    return true;
  }

  void quitarVentaDeLaTanda(int index) {
    if (index < 0 || index >= _pendientes.length) return;
    _pendientes.removeAt(index);
    ventasCargadas.removeAt(index);
    notifyListeners();
  }

  // ─── Guardar el día completo ──────────────────────────────────────────

  bool guardando = false;

  /// Persiste el día entero: crea la sesión, graba cada venta de la tanda
  /// (sin stock) y la cierra sola (arqueo automático). `null` si faltaba la
  /// fecha o la tanda estaba vacía.
  Future<int?> guardarDia() async {
    final fechaElegida = fecha;
    if (fechaElegida == null) {
      error = 'Elegí la fecha del día';
      notifyListeners();
      return null;
    }
    if (_pendientes.isEmpty) {
      error = 'Agregá al menos una venta';
      notifyListeners();
      return null;
    }

    guardando = true;
    error = null;
    notifyListeners();

    try {
      return await cargarDiaHistoricoDesdeVentas(
        db,
        fecha: fechaElegida,
        usuarioId: usuarioId,
        ventas: _pendientes,
      );
    } finally {
      guardando = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    campoTexto.dispose();
    focoCampoPrincipal.dispose();
    super.dispose();
  }
}
