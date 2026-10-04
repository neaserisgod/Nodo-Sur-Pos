// `PuertoLocal`, pero sin dejar abrir una caja propia — fase 3 del
// rediseño "companion sin depender del escritorio". El dueño: "no permite
// vender si no había una sesión abierta al momento de perder la conexión."
// Sin PC alcanzable no hay forma de saber si otro dispositivo (la PC misma,
// más tarde) ya abrió una para hoy, y abrir una propia acá arriesgaría dos
// aperturas del mismo día chocando al sincronizar (`tables/configuracion.dart`,
// comentario de `dispositivoAperturaDesignadoId`: "nunca fusión automática y
// silenciosa de dos aperturas"). El resto de los métodos son un delegado
// directo a `PuertoLocal` — nada de lógica nueva, la política es solo sobre
// `abrirSesion`.

import '../domain/cobro_posnet.dart' show ResultadoOrdenCobro;
import '../domain/descuento.dart' show TipoDescuento;
import '../domain/edicion_masiva_precios.dart' show CampoMonto, TipoAjustePrecio;
import '../domain/edicion_masiva_stock.dart' show TipoAjusteStock;
import '../domain/venta.dart' show LineaVenta, ResultadoTotalVenta;
import 'cliente_companion.dart';
import 'puerto_local.dart';
import 'servicio_companion.dart';
import '../servicios/devolucion_mp.dart' show CobroPoint;

const mensajeSinAperturaOffline = ErrorCompanion(
  0,
  'Sin conexión a la PC — hace falta que haya quedado una caja abierta '
  'antes de perder la conexión. No se puede abrir una nueva desde acá.',
);

class ServicioCompanionOffline implements ServicioCompanion {
  ServicioCompanionOffline(this._local);

  final PuertoLocal _local;

  @override
  Future<int> abrirSesion({
    required int usuarioId,
    required int fondoInicialCentavos,
  }) async {
    throw mensajeSinAperturaOffline;
  }

  @override
  Future<List<UsuarioCompanion>> usuarios() => _local.usuarios();

  // Encargues: delegan tal cual, apartar y entregar funcionan sin la PC (la base local los sincroniza después).
  @override
  Future<List<EncargueCompanion>> encargues() => _local.encargues();

  @override
  Future<int> crearEncargue({required String nombreCliente, required List<ApartadoCompanion> lineas, required int usuarioId}) =>
      _local.crearEncargue(nombreCliente: nombreCliente, lineas: lineas, usuarioId: usuarioId);

  @override
  Future<void> cancelarEncargue(int id, {required int usuarioId}) => _local.cancelarEncargue(id, usuarioId: usuarioId);

  @override
  Future<List<LineaVenta>> lineasDeEncargue(int id) => _local.lineasDeEncargue(id);

  @override
  Future<int> entregarEncargueADeuda(int id, {required int usuarioId}) => _local.entregarEncargueADeuda(id, usuarioId: usuarioId);

  @override
  Future<List<DeudaCompanion>> deudas() => _local.deudas();

  @override
  Future<void> cobrarDeuda(int id, {required int usuarioId, required int sesionCajaId, required bool efectivo}) =>
      _local.cobrarDeuda(id, usuarioId: usuarioId, sesionCajaId: sesionCajaId, efectivo: efectivo);

  @override
  Future<List<ProveedorCompanion>> proveedores() => _local.proveedores();

  @override
  Future<List<CategoriaCompanion>> categorias() => _local.categorias();

  // ─── Configuración (El dueño, 2026-09-19) — delega tal cual, sin política
  // propia: a diferencia de `abrirSesion`, editar reglas de negocio no
  // arriesga duplicar ninguna sesión, así que funciona igual con o sin PC.
  @override
  Future<ConfiguracionNegocioCompanion> configuracionNegocio() => _local.configuracionNegocio();

  @override
  Future<void> actualizarRecargoCigarrillos({
    required int primerAtadoCentavos,
    required int atadoAdicionalCentavos,
    required int sueltoCentavos,
  }) => _local.actualizarRecargoCigarrillos(
    primerAtadoCentavos: primerAtadoCentavos,
    atadoAdicionalCentavos: atadoAdicionalCentavos,
    sueltoCentavos: sueltoCentavos,
  );

  @override
  Future<void> actualizarPasoRedondeo(int montoCentavos) => _local.actualizarPasoRedondeo(montoCentavos);

  @override
  Future<void> actualizarProductoVuelto(int? productoId) => _local.actualizarProductoVuelto(productoId);

  @override
  Future<void> actualizarMarkupCategoria(int categoriaId, int markupBp) =>
      _local.actualizarMarkupCategoria(categoriaId, markupBp);

  @override
  Future<List<MedioDePagoCompanion>> mediosDePago() => _local.mediosDePago();

  @override
  Future<void> renombrarMedioPago(int id, String nombre) => _local.renombrarMedioPago(id, nombre);

  @override
  Future<void> alternarActivoMedioPago(int id, bool activo) => _local.alternarActivoMedioPago(id, activo);

  @override
  Future<int> crearUsuarioNuevo(String nombre) => _local.crearUsuarioNuevo(nombre);

  @override
  Future<void> renombrarUsuarioExistente(int id, String nombre) =>
      _local.renombrarUsuarioExistente(id, nombre);

  @override
  Future<void> alternarActivoUsuarioExistente(int id, bool activo) =>
      _local.alternarActivoUsuarioExistente(id, activo);

  @override
  Future<List<ProductoCompanion>> productos({
    String? busqueda,
    int? proveedorId,
    bool sinProveedor = false,
    bool sinCosto = false,
    bool sinCategoria = false,
    bool sinCodigoBarras = false,
  }) => _local.productos(
    busqueda: busqueda,
    proveedorId: proveedorId,
    sinProveedor: sinProveedor,
    sinCosto: sinCosto,
    sinCategoria: sinCategoria,
    sinCodigoBarras: sinCodigoBarras,
  );

  @override
  Future<List<ProductoCompanion>> productosSinStock() => _local.productosSinStock();

  @override
  Future<ProductoCompanion?> porCodigoBarras(String codigo) => _local.porCodigoBarras(codigo);

  @override
  Future<int> crearProducto({
    required String nombre,
    String? codigoBarras,
    int? categoriaId,
    int? proveedorId,
    required bool esPesable,
    int? precioCentavos,
    int? costoCentavos,
    int? precioPorKiloCentavos,
    int? costoPorKiloCentavos,
    int stock = 0,
    int? stockGramos,
    required int usuarioId,
  }) => _local.crearProducto(
    nombre: nombre,
    codigoBarras: codigoBarras,
    categoriaId: categoriaId,
    proveedorId: proveedorId,
    esPesable: esPesable,
    precioCentavos: precioCentavos,
    costoCentavos: costoCentavos,
    precioPorKiloCentavos: precioPorKiloCentavos,
    costoPorKiloCentavos: costoPorKiloCentavos,
    stock: stock,
    stockGramos: stockGramos,
    usuarioId: usuarioId,
  );

  @override
  Future<void> actualizarProducto(
    int id, {
    required String nombre,
    String? codigoBarras,
    int? categoriaId,
    int? proveedorId,
    required bool esPesable,
    int? precioCentavos,
    int? costoCentavos,
    int? precioPorKiloCentavos,
    int? costoPorKiloCentavos,
    required int stock,
    int? stockGramos,
    required bool activo,
    required int usuarioId,
  }) => _local.actualizarProducto(
    id,
    nombre: nombre,
    codigoBarras: codigoBarras,
    categoriaId: categoriaId,
    proveedorId: proveedorId,
    esPesable: esPesable,
    precioCentavos: precioCentavos,
    costoCentavos: costoCentavos,
    precioPorKiloCentavos: precioPorKiloCentavos,
    costoPorKiloCentavos: costoPorKiloCentavos,
    stock: stock,
    stockGramos: stockGramos,
    activo: activo,
    usuarioId: usuarioId,
  );

  @override
  Future<void> ajustarStock(
    int productoId, {
    required int stock,
    int? stockGramos,
    String? motivo,
    required int usuarioId,
  }) => _local.ajustarStock(
    productoId,
    stock: stock,
    stockGramos: stockGramos,
    motivo: motivo,
    usuarioId: usuarioId,
  );

  @override
  Future<void> ajustarMontoEnLote({
    required List<int> productoIds,
    required CampoMonto campo,
    required TipoAjustePrecio tipo,
    required int valor,
    required int usuarioId,
  }) => _local.ajustarMontoEnLote(
    productoIds: productoIds,
    campo: campo,
    tipo: tipo,
    valor: valor,
    usuarioId: usuarioId,
  );

  @override
  Future<void> ajustarStockEnLote({
    required List<int> productoIds,
    required TipoAjusteStock tipo,
    required int valor,
    required int usuarioId,
    String motivo = 'Ajuste masivo',
  }) => _local.ajustarStockEnLote(
    productoIds: productoIds,
    tipo: tipo,
    valor: valor,
    usuarioId: usuarioId,
    motivo: motivo,
  );

  @override
  Future<void> asignarCategoriaEnLote({
    required List<int> productoIds,
    int? categoriaId,
    required int usuarioId,
  }) => _local.asignarCategoriaEnLote(
    productoIds: productoIds,
    categoriaId: categoriaId,
    usuarioId: usuarioId,
  );

  @override
  Future<void> asignarProveedorEnLote({
    required List<int> productoIds,
    int? proveedorId,
    required int usuarioId,
  }) => _local.asignarProveedorEnLote(
    productoIds: productoIds,
    proveedorId: proveedorId,
    usuarioId: usuarioId,
  );


  @override
  Future<SesionCompanion> sesion() => _local.sesion();

  @override
  Future<EstadoCajaCompanion> estadoCaja() => _local.estadoCaja();

  @override
  Future<EstadoArqueoIntermedioCompanion> calcularArqueoIntermedio({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) => _local.calcularArqueoIntermedio(
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    lataContadoCentavos: lataContadoCentavos,
  );

  @override
  Future<void> confirmarArqueoIntermedio({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
  }) => _local.confirmarArqueoIntermedio(
    usuarioId: usuarioId,
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    lataContadoCentavos: lataContadoCentavos,
  );

  /// A diferencia de [abrirSesion] (bloqueada arriba), CERRAR sin la PC sí
  /// se permite (El dueño, 2026-09-19: "que funcione también sin la PC") — no
  /// arriesga duplicar ninguna sesión, solo escribe sobre la que ya existe.
  /// El aviso de que el cálculo puede no reflejar algo que todavía no
  /// sincronizó a este celular vive en la UI (`AvisoModoLocal`, mismo
  /// lenguaje visual), no acá.
  @override
  Future<ResumenCierreCompanion> calcularCierre({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) => _local.calcularCierre(
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    lataContadoCentavos: lataContadoCentavos,
  );

  @override
  Future<void> confirmarCierre({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
    String? nota,
  }) => _local.confirmarCierre(
    usuarioId: usuarioId,
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    lataContadoCentavos: lataContadoCentavos,
    nota: nota,
  );

  @override
  Future<ResumenCierreCompanion> detalleCierre(int sesionId) => _local.detalleCierre(sesionId);

  @override
  Future<List<VentaDelHistorialCompanion>> historialDeVentas({
    required DateTime desde,
    required DateTime hasta,
    MedioVentaHistorialCompanion? filtroMedio,
  }) => _local.historialDeVentas(desde: desde, hasta: hasta, filtroMedio: filtroMedio);

  @override
  Future<void> anularVenta({
    required int ventaId,
    required int usuarioId,
    required String motivo,
  }) => _local.anularVenta(ventaId: ventaId, usuarioId: usuarioId, motivo: motivo);

  @override
  Future<CobroPoint?> cobroPointDeVenta(int ventaId) => _local.cobroPointDeVenta(ventaId);

  @override
  Future<DetalleVentaCompanion> detalleVenta(int ventaId) => _local.detalleVenta(ventaId);

  @override
  Future<List<SesionCerradaCompanion>> sesionesCerradas({int limite = 30}) =>
      _local.sesionesCerradas(limite: limite);

  @override
  Future<int> guardarDiaHistorico({
    required DateTime fecha,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) => _local.guardarDiaHistorico(fecha: fecha, usuarioId: usuarioId, ventas: ventas);

  @override
  Future<List<DiaHistoricoCompanion>> diasHistoricos() => _local.diasHistoricos();

  @override
  Future<List<VentaHistoricaResumenCompanion>> ventasDeDiaHistorico(int sesionId) =>
      _local.ventasDeDiaHistorico(sesionId);

  @override
  Future<ResumenDiaHistoricoCompanion> resumenDiaHistorico(int sesionId) =>
      _local.resumenDiaHistorico(sesionId);

  @override
  Future<void> agregarVentasADiaHistorico({
    required int sesionId,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) => _local.agregarVentasADiaHistorico(sesionId: sesionId, usuarioId: usuarioId, ventas: ventas);

  @override
  Future<void> eliminarVentaHistorica({
    required int sesionId,
    required int ventaId,
    required int usuarioId,
  }) => _local.eliminarVentaHistorica(sesionId: sesionId, ventaId: ventaId, usuarioId: usuarioId);

  @override
  Future<void> eliminarDiaHistorico(int sesionId) => _local.eliminarDiaHistorico(sesionId);

  @override
  Future<({int ventaId, int totalCentavos})> cobrarVirtualAMano({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    required String canal,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
  }) => _local.cobrarVirtualAMano(
    lineas: lineas,
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    canal: canal,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
    encargueId: encargueId,
  );

  @override
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})> iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  }) => _local.iniciarCobroPosnet(
    lineas: lineas,
    canal: canal,
    sesionCajaId: sesionCajaId,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
  );

  @override
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) =>
      _local.consultarEstadoPosnet(ordenIdMp);

  @override
  Future<({int ventaId, int totalCentavos})> confirmarCobroPosnet({
    required int ordenPendienteId,
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
  }) => _local.confirmarCobroPosnet(
    ordenPendienteId: ordenPendienteId,
    lineas: lineas,
    canal: canal,
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
    encargueId: encargueId,
  );

  @override
  Future<void> resolverCobroPosnetNoAprobado({
    required int ordenPendienteId,
    required String estado,
  }) => _local.resolverCobroPosnetNoAprobado(ordenPendienteId: ordenPendienteId, estado: estado);

  @override
  Future<void> cancelarCobroPosnet({required int ordenPendienteId, String? ordenIdMp}) =>
      _local.cancelarCobroPosnet(ordenPendienteId: ordenPendienteId, ordenIdMp: ordenIdMp);

  @override
  Future<Map<int, int>> saldosProveedores() => _local.saldosProveedores();

  @override
  Future<int> pagarProveedor({
    required int proveedorId,
    required int usuarioId,
    required int montoCentavos,
    required String origen,
    int? sesionCajaId,
    String? nota,
  }) => _local.pagarProveedor(
    proveedorId: proveedorId,
    usuarioId: usuarioId,
    montoCentavos: montoCentavos,
    origen: origen,
    sesionCajaId: sesionCajaId,
    nota: nota,
  );

  @override
  Future<int> registrarGasto({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) => _local.registrarGasto(
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    montoCentavos: montoCentavos,
    medio: medio,
    motivo: motivo,
  );

  @override
  Future<int> registrarIngreso({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) => _local.registrarIngreso(
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    montoCentavos: montoCentavos,
    medio: medio,
    motivo: motivo,
  );

  @override
  Future<({int? gramos, List<ProductoCompanion> resultados})> buscarVenta(
    String texto, {
    bool exigirStock = true,
  }) => _local.buscarVenta(texto, exigirStock: exigirStock);

  @override
  Future<ResultadoTotalVenta> calcularVenta({
    required List<LineaVenta> lineas,
    required String medio,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  }) => _local.calcularVenta(
    lineas: lineas,
    medio: medio,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
  );

  @override
  Future<({int ventaId, int totalCentavos})> cobrarEfectivo({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
  }) => _local.cobrarEfectivo(
    lineas: lineas,
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
    encargueId: encargueId,
  );
}
