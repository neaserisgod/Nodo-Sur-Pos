// Implementación de `ServicioCompanion` contra una base propia del celular
// (companion Android sin depender del escritorio, fase 2 del rediseño
// 2026-09-15) — llama exactamente a los mismos repositorios de `lib/data/`
// que ya usa `lib/servidor/servidor_companion.dart` para el celular vía
// HTTP, pero directo, en el mismo proceso, sin red. Mismo dominio, mismas
// reglas de negocio, la única diferencia es el transporte (Regla 3: ninguna
// fórmula nueva vive acá).
//
// Import con prefijo para cada archivo de `data/` que tiene una función con
// el mismo nombre que un método de esta clase (`crearProducto`,
// `abrirSesion`, etc.) — sin el prefijo, Dart resuelve el nombre sin
// calificar dentro de un método de instancia contra el propio método (`this`
// implícito) antes que contra la función top-level importada, así que
// `crearProducto(db, ...)` adentro de `PuertoLocal.crearProducto` se
// llamaría a sí mismo en vez de al repositorio.

import '../data/busqueda_productos.dart' as busqueda;
import '../data/database.dart';
import '../data/repositorio_arqueo_intermedio.dart' as repo_arqueo;
import '../data/cobro_posnet.dart' as mp;
import '../data/repositorio_carga_historica.dart' as repo_carga_historica;
import '../data/repositorio_cierre.dart' as repo_cierre;
import '../data/repositorio_cobro.dart' as repo_cobro;
import '../data/repositorio_configuracion.dart' as repo_configuracion;
import '../data/repositorio_deuda_proveedores.dart' as repo_deuda;
import '../data/repositorio_edicion_venta.dart' as repo_edicion_venta;
import '../data/repositorio_encargues.dart' as repo_encargues;
import '../data/repositorio_gastos.dart' as repo_gastos;
import '../data/repositorio_historial.dart' as repo_historial;
import '../data/repositorio_historial_ventas.dart' as repo_historial_ventas;
import '../data/repositorio_ingresos.dart' as repo_ingresos;
import '../data/repositorio_medios_pago.dart' as repo_medios_pago;
import '../data/repositorio_productos.dart' as repo_productos;
import '../data/repositorio_promos.dart' as repo_promos;
import '../data/repositorio_ticket.dart' as repo_ticket;
import '../data/repositorio_faltantes.dart' as repo_faltantes;
import '../data/repositorio_faltantes.dart' show DestinoFaltante;
import '../domain/faltantes_cierre.dart' show CajaDelCierre;
import '../data/repositorio_usuarios.dart' as repo_usuarios;
import '../data/repositorio_pendientes.dart' as repo_pendientes;
import '../data/repositorio_ventas.dart' as repo_ventas;
import '../domain/cobro_posnet.dart' show ResultadoOrdenCobro, clasificarEstadoOrden;
import '../domain/caja.dart' show diferenciaArqueo;
import '../domain/descuento.dart' show TipoDescuento;
import '../domain/edicion_masiva_precios.dart' show CampoMonto, TipoAjustePrecio;
import '../domain/edicion_masiva_stock.dart' show TipoAjusteStock;
import '../domain/medio_pago.dart' show ComposicionPago, composicionPagoDesdeTexto;
import '../domain/venta.dart' show LineaVenta, ResultadoTotalVenta, Venta;
import '../data/cobro_posnet.dart' show PasarelaPoint;
import '../servicios/impresion_posnet_nube.dart' show imprimirTicketPosnet;
import '../servicios/marca_actual.dart' show marcaDeBase;
import '../servicios/pasarela_point_nube.dart';
import 'cliente_companion.dart';
import 'servicio_companion.dart';
import 'sync_nube_companion.dart';
import '../servicios/devolucion_mp.dart' as devolucion show cobroPointDeVenta;
import '../servicios/devolucion_mp.dart' show CobroPoint;

/// Convierte una fila de drift en el mismo DTO que hoy arma
/// `ProductoCompanion.desdeJson` a partir de la respuesta HTTP — un solo
/// lugar para esta traducción (Regla 3), reusado por cada método de acá
/// abajo que devuelve productos.
ProductoCompanion _productoDesdeFila(Producto p) => ProductoCompanion(
  id: p.id,
  nombre: p.nombre,
  codigoBarras: p.codigoBarras,
  categoriaId: p.categoriaId,
  proveedorId: p.proveedorId,
  esPesable: p.esPesable,
  precioCentavos: p.precioCentavos,
  costoCentavos: p.costoCentavos,
  precioPorKiloCentavos: p.precioPorKiloCentavos,
  costoPorKiloCentavos: p.costoPorKiloCentavos,
  stock: p.stock,
  stockGramos: p.stockGramos,
  activo: p.activo,
  tipoCigarrillo: p.tipoCigarrillo,
);

/// Mismo mapeo, campo por campo, que `_resumenDiaAJson` en
/// `servidor_companion.dart` — ahí arma un JSON, acá el DTO Dart
/// directo, pero es la misma traducción de `ResumenDiaHistorico` (dominio)
/// a `ResumenDiaHistoricoCompanion` (Regla 3: nunca dos veces la misma
/// fórmula, y esto no es más que reordenar nombres de campos).
ResumenDiaHistoricoCompanion _resumenDesdeDominio(
  repo_carga_historica.ResumenDiaHistorico resumen,
) => ResumenDiaHistoricoCompanion(
  totalCentavos: resumen.totalCentavos,
  efectivoCentavos: resumen.efectivoCentavos,
  mercadoPagoCentavos: resumen.mercadoPagoCentavos,
  cigarrillosListaCentavos: resumen.cigarrillosListaCentavos,
  vendidoSinCostoCentavos: resumen.vendidoSinCostoCentavos,
  productosSinDatos: [
    for (final p in resumen.productosSinDatos)
      ProductoSinDatosCompanion(
        productoId: p.productoId,
        nombreProducto: p.nombreProducto,
        vendidoCentavos: p.vendidoCentavos,
        sinProveedor: p.sinProveedor,
        sinCosto: p.sinCosto,
      ),
  ],
  porProveedor: [
    for (final p in resumen.porProveedor)
      ResumenProveedorDiaCompanion(
        proveedorId: p.proveedorId,
        nombreProveedor: p.nombreProveedor,
        vendidoCentavos: p.vendidoCentavos,
        costoRealCentavos: p.costoRealCentavos,
        gananciaCentavos: p.gananciaCentavos,
      ),
  ],
);

/// Combina `ResumenCierre` (arqueo/cigarrillos/redondeo/reserva) con
/// `ResumenDiaHistorico` (desglose por proveedor, ya traducido por
/// `_resumenDesdeDominio`) en un solo DTO — usado tanto por [calcularCierre]
/// como por [detalleCierre] (Regla 3, mismo criterio que
/// `_resumenCierreAJson` del servidor).
ResumenCierreCompanion _resumenCierreCompanionDesde(
  repo_cierre.ResumenCierre resumen,
  repo_carga_historica.ResumenDiaHistorico resumenDiaDominio, {
  String? nota,
  int? efectivoContadoCentavos,
  int? mpContadoCentavos,
  int? lataContadoCentavos,
}) {
  final resumenDia = _resumenDesdeDominio(resumenDiaDominio);
  return ResumenCierreCompanion(
    efectivoEsperadoCentavos: resumen.efectivoEsperadoCentavos,
    diferenciaCentavos: resumen.diferenciaCentavos,
    mpEsperadoCentavos: resumen.mpEsperadoCentavos,
    mpDiferenciaCentavos: resumen.mpDiferenciaCentavos,
    lataFinalCentavos: resumen.lataFinalCentavos,
    lataDiferenciaCentavos: resumen.lataDiferenciaCentavos,
    separadoCentavos: resumen.separacionCigarrillos.separadoCentavos,
    pendienteCentavos: resumen.separacionCigarrillos.pendienteCentavos,
    esSeparacionParcial: resumen.separacionCigarrillos.esSeparacionParcial,
    redondeoAcumuladoCentavos: resumen.redondeoAcumuladoCentavos,
    reservaDiariaFijosCentavos: resumen.reservaDiariaFijosCentavos,
    totalCentavos: resumenDia.totalCentavos,
    efectivoCentavos: resumenDia.efectivoCentavos,
    mercadoPagoCentavos: resumenDia.mercadoPagoCentavos,
    cigarrillosListaCentavos: resumenDia.cigarrillosListaCentavos,
    vendidoSinCostoCentavos: resumenDia.vendidoSinCostoCentavos,
    productosSinDatos: resumenDia.productosSinDatos,
    porProveedor: resumenDia.porProveedor,
    nota: nota,
    efectivoContadoCentavos: efectivoContadoCentavos,
    mpContadoCentavos: mpContadoCentavos,
    lataContadoCentavos: lataContadoCentavos,
  );
}

class PuertoLocal implements ServicioCompanion {
  PuertoLocal(this.db, {this.pasarelaDePrueba});

  final AppDatabase db;

  /// Solo para tests: la pasarela de cobro con la terminal. En la app real sale de la cuenta vinculada (`_pasarela`).
  final Future<PasarelaPoint> Function()? pasarelaDePrueba;

  @override
  Future<List<UsuarioCompanion>> usuarios() async {
    final filas = await db.select(db.usuarios).get();
    return [
      for (final u in filas) UsuarioCompanion(id: u.id, nombre: u.nombre, activo: u.activo),
    ];
  }

  // ─── Encargues por apartado ──────────────────────────────────────────

  @override
  Future<List<EncargueCompanion>> encargues() async {
    final lista = await repo_encargues.listarEnarguesPendientes(db);
    return [
      for (final e in lista)
        EncargueCompanion(id: e.id, nombreCliente: e.nombreCliente, desde: e.desde, lineas: [for (final l in e.lineas) l.texto], senaCentavos: e.senaCentavos),
    ];
  }

  @override
  Future<int> crearEncargue({
    required String nombreCliente,
    required List<ApartadoCompanion> lineas,
    required int usuarioId,
    int senaCentavos = 0,
    bool senaEsEfectivo = true,
  }) async {
    try {
      return await repo_encargues.crearEncargueApartando(
        db,
        nombreCliente: nombreCliente,
        lineas: [
          for (final l in lineas)
            repo_encargues.LineaEncargueNueva(productoId: l.productoId, cantidad: l.cantidad, gramos: l.gramos),
        ],
        usuarioId: usuarioId,
        // La seña entra a la caja abierta de esta base, como en la PC (El dueño, 2026-10-09: independizar el celular).
        senaCentavos: senaCentavos,
        senaEsEfectivo: senaEsEfectivo,
        sesionCajaId: senaCentavos > 0 ? (await repo_ventas.sesionAbierta(db))?.id : null,
      );
    } on repo_encargues.EncargueSinStock catch (e) {
      throw ErrorCompanion(409, 'No alcanza el stock de ${e.nombreProducto}.');
    } on ArgumentError catch (e) {
      throw ErrorCompanion(400, '${e.message}');
    }
  }

  @override
  Future<void> cancelarEncargue(int id, {required int usuarioId}) async {
    try {
      // Con seña, la devolución sale de la caja abierta de esta base, como en la PC.
      await repo_encargues.cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: (await repo_ventas.sesionAbierta(db))?.id);
    } on ArgumentError catch (e) {
      throw ErrorCompanion(400, '${e.message}');
    }
  }

  @override
  Future<List<LineaVenta>> lineasDeEncargue(int id) => repo_encargues.lineasParaEntregar(db, id);

  @override
  Future<int> entregarEncargueADeuda(int id, {required int usuarioId}) async {
    final total = await repo_encargues.entregarEncargueADeuda(db, id, usuarioId: usuarioId);
    if (total == null) throw ErrorCompanion(409, 'Ese encargue ya no está pendiente.');
    return total;
  }

  @override
  Future<List<DeudaCompanion>> deudas() async {
    final lista = await repo_encargues.listarDeudas(db);
    return [
      for (final d in lista)
        DeudaCompanion(id: d.id, nombreCliente: d.nombreCliente, detalle: d.detalle, montoCentavos: d.montoCentavos, desde: d.desde),
    ];
  }

  @override
  Future<void> cobrarDeuda(int id, {required int usuarioId, required int sesionCajaId, required bool efectivo}) async {
    try {
      await repo_pendientes.cobrarDeuda(db, pendienteId: id, sesionCajaId: sesionCajaId, usuarioId: usuarioId, efectivo: efectivo);
    } on repo_ventas.SesionCerradaException {
      throw ErrorCompanion(409, 'La caja ya se cerró, este cobro no se guardó');
    } on repo_pendientes.PendienteYaResueltoException {
      throw ErrorCompanion(409, 'Esa deuda ya estaba cobrada');
    }
  }

  @override
  Future<List<ProveedorCompanion>> proveedores() async {
    final filas = await repo_productos.listarProveedores(db);
    return [
      for (final p in filas)
        ProveedorCompanion(id: p.id, codigo: p.codigo, nombre: p.nombre),
    ];
  }

  @override
  Future<List<CategoriaCompanion>> categorias() async {
    final filas = await repo_productos.listarCategorias(db);
    return [
      for (final c in filas)
        CategoriaCompanion(id: c.id, nombre: c.nombre, markupDefaultBp: c.markupDefaultBp),
    ];
  }

  // ─── Configuración (El dueño, 2026-09-19) ──────────────────────────────────

  @override
  Future<ConfiguracionNegocioCompanion> configuracionNegocio() async {
    final c = await repo_configuracion.configuracionNegocioActual(db);
    return ConfiguracionNegocioCompanion(
      recargoPrimerAtadoCentavos: c.recargoPrimerAtadoCentavos,
      recargoAtadoAdicionalCentavos: c.recargoAtadoAdicionalCentavos,
      recargoSueltoCentavos: c.recargoSueltoCentavos,
      pasoRedondeoCentavos: c.pasoRedondeoCentavos,
      productoVueltoId: c.productoVueltoId,
    );
  }

  @override
  Future<void> actualizarRecargoCigarrillos({
    required int primerAtadoCentavos,
    required int atadoAdicionalCentavos,
    required int sueltoCentavos,
  }) => repo_configuracion.configurarRecargoCigarrillos(
    db,
    primerAtadoCentavos: primerAtadoCentavos,
    atadoAdicionalCentavos: atadoAdicionalCentavos,
    sueltoCentavos: sueltoCentavos,
  );

  @override
  Future<void> actualizarPasoRedondeo(int montoCentavos) =>
      repo_configuracion.configurarPasoRedondeo(db, montoCentavos);

  @override
  Future<void> actualizarProductoVuelto(int? productoId) =>
      repo_configuracion.configurarProductoVuelto(db, productoId);

  @override
  Future<void> actualizarMarkupCategoria(int categoriaId, int markupBp) =>
      repo_productos.actualizarMarkupCategoria(db, categoriaId: categoriaId, markupBp: markupBp);

  @override
  Future<List<MedioDePagoCompanion>> mediosDePago() async {
    final filas = await repo_medios_pago.listarMediosDePago(db);
    return [
      for (final m in filas)
        MedioDePagoCompanion(id: m.id, nombre: m.nombre, esEfectivo: m.esEfectivo, activo: m.activo),
    ];
  }

  @override
  Future<void> renombrarMedioPago(int id, String nombre) =>
      repo_medios_pago.renombrarMedioDePago(db, id, nombre);

  @override
  Future<void> alternarActivoMedioPago(int id, bool activo) => activo
      ? repo_medios_pago.activarMedioDePago(db, id)
      : repo_medios_pago.desactivarMedioDePago(db, id);

  @override
  Future<int> crearUsuarioNuevo(String nombre) => repo_usuarios.crearUsuario(db, nombre);

  @override
  Future<void> renombrarUsuarioExistente(int id, String nombre) =>
      repo_usuarios.renombrarUsuario(db, id, nombre);

  @override
  Future<void> alternarActivoUsuarioExistente(int id, bool activo) =>
      activo ? repo_usuarios.activarUsuario(db, id) : repo_usuarios.desactivarUsuario(db, id);

  @override
  Future<List<ProductoCompanion>> productos({
    String? busqueda,
    int? proveedorId,
    bool sinProveedor = false,
    bool sinCosto = false,
    bool sinCategoria = false,
    bool sinCodigoBarras = false,
  }) async {
    final filas = await repo_productos.listarProductos(
      db,
      busqueda: busqueda,
      proveedorId: proveedorId,
      sinProveedor: sinProveedor,
      sinCosto: sinCosto,
      sinCategoria: sinCategoria,
      sinCodigoBarras: sinCodigoBarras,
    );
    return [for (final p in filas) _productoDesdeFila(p)];
  }

  /// Mismo criterio que `/productos/sin-stock` del servidor: agotados o en
  /// negativo, de todos los proveedores juntos, agotados primero y
  /// alfabético dentro de cada grupo.
  @override
  Future<List<ProductoCompanion>> productosSinStock() async {
    final filas = await repo_productos.listarProductos(db);
    final agotados = repo_productos.ordenarAgotadosPrimero(
      filas.where(repo_productos.productoAgotado).toList(),
    );
    return [for (final p in agotados) _productoDesdeFila(p)];
  }

  @override
  Future<ProductoCompanion?> porCodigoBarras(String codigo) async {
    final producto = await repo_productos.productoPorCodigoBarras(db, codigo);
    return producto == null ? null : _productoDesdeFila(producto);
  }

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
  }) {
    return repo_productos.crearProducto(
      db,
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
  }

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
  }) {
    return repo_productos.actualizarProducto(
      db,
      id: id,
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
  }

  @override
  Future<void> ajustarStock(
    int productoId, {
    required int stock,
    int? stockGramos,
    String? motivo,
    required int usuarioId,
  }) {
    return repo_productos.ajustarStockRapido(
      db,
      productoId: productoId,
      usuarioId: usuarioId,
      stock: stock,
      stockGramos: stockGramos,
      motivo: motivo,
    );
  }

  // Editor masivo (El dueño, 2026-09-19: "editor masivo, ya sea de precios
  // costo stock etc etc") — delegado directo a cada función en lote de
  // `repositorio_productos.dart` (Regla 3: mismo camino que `ClienteCompanion`
  // usa por HTTP, acá sin red de por medio).
  @override
  Future<void> ajustarMontoEnLote({
    required List<int> productoIds,
    required CampoMonto campo,
    required TipoAjustePrecio tipo,
    required int valor,
    required int usuarioId,
  }) {
    return repo_productos.ajustarMontoEnLote(
      db,
      productoIds: productoIds,
      campo: campo,
      tipo: tipo,
      valor: valor,
      usuarioId: usuarioId,
    );
  }

  @override
  Future<void> ajustarStockEnLote({
    required List<int> productoIds,
    required TipoAjusteStock tipo,
    required int valor,
    required int usuarioId,
    String motivo = 'Ajuste masivo',
  }) {
    return repo_productos.ajustarStockEnLote(
      db,
      productoIds: productoIds,
      tipo: tipo,
      valor: valor,
      usuarioId: usuarioId,
      motivo: motivo,
    );
  }

  @override
  Future<void> asignarCategoriaEnLote({
    required List<int> productoIds,
    int? categoriaId,
    required int usuarioId,
  }) {
    return repo_productos.asignarCategoriaEnLote(
      db,
      productoIds: productoIds,
      categoriaId: categoriaId,
      usuarioId: usuarioId,
    );
  }

  @override
  Future<void> asignarProveedorEnLote({
    required List<int> productoIds,
    int? proveedorId,
    required int usuarioId,
  }) {
    return repo_productos.asignarProveedorEnLote(
      db,
      productoIds: productoIds,
      proveedorId: proveedorId,
      usuarioId: usuarioId,
    );
  }

  /// Mismo criterio que `GET /sesion` del servidor — ver ese comentario en
  /// `servidor_companion.dart` para el porqué de cada campo.
  @override
  Future<SesionCompanion> sesion() async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      final sugerido = await repo_cierre.fondoInicialSugeridoCentavos(db);
      final lataQueSeArrastra = await repo_ventas.lataQueSeArrastraCentavos(db);
      final mpQueSeArrastra = await repo_ventas.mpQueSeArrastraCentavos(db);
      return SesionCompanion(
        abierta: false,
        fondoInicialSugeridoCentavos: sugerido,
        lataQueSeArrastraCentavos: lataQueSeArrastra,
        mpQueSeArrastraCentavos: mpQueSeArrastra,
      );
    }
    final ultimoArqueo = await repo_arqueo.fechaUltimoArqueoIntermedio(db, sesion.id);
    final ultimo = (await repo_arqueo.arqueosDelTurno(db, sesion.id)).lastOrNull;
    final movidas = ultimo == null ? null : await repo_cierre.cajasMovidasDesde(db, sesion.id, ultimo.fecha);
    return SesionCompanion(
      abierta: true,
      id: sesion.id,
      fechaApertura: sesion.fechaApertura,
      fechaUltimoArqueoIntermedio: ultimoArqueo,
      ultimoArqueoEfectivoCentavos: movidas?.efectivo ?? true ? null : ultimo?.efectivoContadoCentavos,
      ultimoArqueoMpCentavos: movidas?.mp ?? true ? null : ultimo?.mpContadoCentavos,
    );
  }

  /// Mismo criterio que `GET /caja/estado` del servidor (`estadoCajaEnVivo`
  /// + `resumenDiaHistorico` + `cantidadVentasDelDia`, las tres en
  /// paralelo) — ver ese comentario en `servidor_companion.dart` para el
  /// porqué completo. Acá no hay JSON de por medio: se arman los DTOs
  /// directo desde los tipos de dominio (Regla 3, misma fórmula que ya usa
  /// el servidor, solo sin la vuelta HTTP).
  @override
  Future<EstadoCajaCompanion> estadoCaja() async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      throw const ErrorCompanion(409, 'No hay caja abierta');
    }
    final futuroEstado = repo_cierre.estadoCajaEnVivo(db, sesion.id);
    final futuroResumen = repo_carga_historica.resumenDiaHistorico(db, sesion.id);
    final futuroCantidadVentas = repo_cierre.cantidadVentasDelDia(db, sesion.id);
    final estado = await futuroEstado;
    final resumen = await futuroResumen;
    final cantidadVentas = await futuroCantidadVentas;
    return EstadoCajaCompanion(
      sesionId: sesion.id,
      fechaApertura: sesion.fechaApertura,
      efectivoEsperadoCentavos: estado.efectivoEsperadoCentavos,
      mpEsperadoCentavos: estado.mpEsperadoCentavos,
      redondeoAcumuladoCentavos: estado.redondeoAcumuladoCentavos,
      lataInicialCentavos: estado.lataInicialCentavos,
      cantidadVentas: cantidadVentas,
      resumen: _resumenDesdeDominio(resumen),
    );
  }

  /// Mismo criterio que `POST /sesion/arqueo-intermedio/calcular` del
  /// servidor: `calcularResumenCierre` para efectivo/MP, `lataEsperadaIntermedia`
  /// aparte para la lata (no la de un cierre real, que asume separado todo
  /// lo vendido hasta ahora — acá se compara contra lo que debería seguir
  /// habiendo SIN separar).
  @override
  Future<EstadoArqueoIntermedioCompanion> calcularArqueoIntermedio({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      throw const ErrorCompanion(409, 'No hay caja abierta');
    }
    final futuroResumen = repo_cierre.calcularResumenCierre(
      db,
      sesionId: sesion.id,
      efectivoContadoCentavos: efectivoContadoCentavos,
      mpContadoCentavos: mpContadoCentavos,
    );
    final futuroLataEsperada = repo_arqueo.lataEsperadaIntermedia(db, sesion.id);
    final resumen = await futuroResumen;
    final lataEsperada = await futuroLataEsperada;
    return EstadoArqueoIntermedioCompanion(
      efectivoEsperadoCentavos: resumen.efectivoEsperadoCentavos,
      diferenciaCentavos: resumen.diferenciaCentavos,
      mpEsperadoCentavos: resumen.mpEsperadoCentavos,
      mpDiferenciaCentavos: resumen.mpDiferenciaCentavos,
      lataEsperadoCentavos: lataEsperada,
      lataDiferenciaCentavos: lataContadoCentavos == null
          ? null
          : diferenciaArqueo(contadoCentavos: lataContadoCentavos, esperadoCentavos: lataEsperada),
    );
  }

  @override
  Future<void> confirmarArqueoIntermedio({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
  }) async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      throw const ErrorCompanion(409, 'No hay caja abierta');
    }
    await repo_arqueo.registrarArqueoIntermedio(
      db,
      sesionId: sesion.id,
      usuarioId: usuarioId,
      efectivoContadoCentavos: efectivoContadoCentavos,
      mpContadoCentavos: mpContadoCentavos,
      lataContadoCentavos: lataContadoCentavos,
    );
  }

  /// Mismo criterio que `POST /sesion/cerrar/calcular` del servidor
  /// (El dueño, 2026-09-19: "que deje cerrar caja desde el celular") —
  /// `calcularResumenCierre` para el arqueo, `resumenDiaHistorico` para el
  /// desglose por proveedor, reusando `_resumenDesdeDominio` (Regla 3, la
  /// misma traducción que ya usa `resumenDiaHistorico` de acá abajo).
  @override
  Future<ResumenCierreCompanion> calcularCierre({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      throw const ErrorCompanion(409, 'No hay caja abierta');
    }
    final futuroResumen = repo_cierre.calcularResumenCierre(
      db,
      sesionId: sesion.id,
      efectivoContadoCentavos: efectivoContadoCentavos,
      mpContadoCentavos: mpContadoCentavos,
      lataContadoCentavos: lataContadoCentavos,
    );
    final futuroResumenDia = repo_carga_historica.resumenDiaHistorico(db, sesion.id);
    return _resumenCierreCompanionDesde(await futuroResumen, await futuroResumenDia);
  }

  /// Detalle de un cierre YA cerrado (El dueño, 2026-09-19) — mismo cálculo
  /// que `GET /sesiones/cerradas/<id>/detalle` del servidor:
  /// `calcularResumenCierre` no exige sesión `ABIERTA`, así que recalcularlo
  /// con los conteos ya guardados en la fila da el mismo desglose que se
  /// vio al cerrar, sin haber cacheado nada de esto aparte.
  @override
  Future<ResumenCierreCompanion> detalleCierre(int sesionId) async {
    final sesion = await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.id.equals(sesionId))).getSingleOrNull();
    if (sesion == null || sesion.estado != 'CERRADA') {
      throw const ErrorCompanion(404, 'No hay ningún cierre real con ese id');
    }
    final futuroResumen = repo_cierre.calcularResumenCierre(
      db,
      sesionId: sesionId,
      efectivoContadoCentavos: sesion.efectivoContadoCentavos ?? 0,
      mpContadoCentavos: sesion.mpContadoCentavos,
      lataContadoCentavos: sesion.lataContadoCentavos,
    );
    final futuroResumenDia = repo_carga_historica.resumenDiaHistorico(db, sesionId);
    return _resumenCierreCompanionDesde(
      await futuroResumen,
      await futuroResumenDia,
      nota: sesion.nota,
      efectivoContadoCentavos: sesion.efectivoContadoCentavos,
      mpContadoCentavos: sesion.mpContadoCentavos,
      lataContadoCentavos: sesion.lataContadoCentavos,
    );
  }

  /// El dueño, 2026-09-19: "que funcione también sin la PC" — a diferencia de
  /// `abrirSesion` (bloqueada en `ServicioCompanionOffline`, nunca llega
  /// hasta acá sin PC), cerrar sí escribe directo sobre la base local
  /// sincronizada por Supabase: no arriesga duplicar ninguna sesión, solo
  /// cierra la que ya existe. El riesgo de que el cálculo no refleje algo
  /// que todavía no sincronizó a este celular se avisa en la UI, no acá.
  @override
  Future<void> confirmarCierre({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
    String? nota,
  }) async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) {
      throw const ErrorCompanion(409, 'No hay caja abierta');
    }
    try {
      await repo_cierre.cerrarSesion(
        db,
        sesionId: sesion.id,
        usuarioId: usuarioId,
        efectivoContadoCentavos: efectivoContadoCentavos,
        mpContadoCentavos: mpContadoCentavos,
        lataContadoCentavos: lataContadoCentavos,
        nota: nota,
      );
    } on repo_cierre.SesionYaNoAbiertaException {
      throw const ErrorCompanion(409, 'La caja ya se cerró desde otro lado mientras tanto');
    }
  }

  /// Mismo criterio que `GET /historial/ventas` del servidor — traduce el
  /// enum de dominio (`MedioVentaHistorial`) al de la companion por
  /// nombre, mismo mecanismo que ya usa el servidor para el filtro entrante.
  @override
  Future<List<VentaDelHistorialCompanion>> historialDeVentas({
    required DateTime desde,
    required DateTime hasta,
    MedioVentaHistorialCompanion? filtroMedio,
  }) async {
    final filtroDominio = filtroMedio == null
        ? null
        : repo_historial_ventas.MedioVentaHistorial.values.firstWhere(
            (m) => m.name == filtroMedio.name,
          );
    final ventas = await repo_historial_ventas.historialDeVentas(
      db,
      desde: desde,
      hasta: hasta,
      filtroMedio: filtroDominio,
    );
    return [
      for (final v in ventas)
        VentaDelHistorialCompanion(
          ventaId: v.ventaId,
          numero: v.numero,
          fecha: v.fecha,
          totalCentavos: v.totalCentavos,
          medio: MedioVentaHistorialCompanion.values.firstWhere((m) => m.name == v.medio.name),
          detalle: v.detalle,
          anulada: v.anulada,
          sesionAbierta: v.sesionAbierta,
        ),
    ];
  }

  @override
  Future<void> anularVenta({
    required int ventaId,
    required int usuarioId,
    required String motivo,
  }) => repo_edicion_venta.anularVenta(
    db,
    ventaId: ventaId,
    usuarioId: usuarioId,
    motivo: motivo,
  );

  @override
  Future<CobroPoint?> cobroPointDeVenta(int ventaId) => devolucion.cobroPointDeVenta(db, ventaId);

  /// Mismo criterio que `GET /ventas/<id>/detalle` del servidor —
  /// `ticketDeVenta` es el mismo `Ticket` de dominio que arma la impresión
  /// (Regla 3), acá traducido a `DetalleVentaCompanion` en vez de a JSON.
  @override
  Future<DetalleVentaCompanion> detalleVenta(int ventaId) async {
    final ticket = await repo_ticket.ticketDeVenta(db, ventaId);
    return DetalleVentaCompanion(
      fecha: ticket.fecha,
      vendedor: ticket.vendedor,
      lineas: [
        for (final l in ticket.lineas)
          LineaTicketCompanion(
            nombreProducto: l.nombreProducto,
            cantidad: l.cantidad,
            gramos: l.gramos,
            subtotalCentavos: l.subtotalCentavos,
          ),
      ],
      recargoCigarrillosCentavos: ticket.desglose.recargoCigarrillosCentavos,
      descuentoCentavos: ticket.desglose.descuentoCentavos,
      redondeoCentavos: ticket.desglose.redondeoCentavos,
      totalCentavos: ticket.totalCentavos,
    );
  }

  /// Mismo criterio que `GET /sesiones/cerradas` del servidor —
  /// `listarDias` es el mismo `listarDias` que ya usa el Historial de
  /// escritorio (Regla 3), excluyendo acá los días de carga histórica
  /// (nunca tuvieron un arqueo de verdad).
  @override
  Future<List<SesionCerradaCompanion>> sesionesCerradas({int limite = 30}) async {
    final dias = await repo_historial.listarDias(db);
    final reales = dias
        .where((d) => d.sesion.nota != repo_carga_historica.notaCargaHistorica)
        .take(limite);
    return [
      for (final d in reales)
        SesionCerradaCompanion(
          sesionId: d.sesion.id,
          fechaApertura: d.sesion.fechaApertura,
          fechaCierre: d.sesion.fechaCierre,
          nombreEmpleado: d.nombreEmpleado,
          totalVendidoCentavos: d.totalVendidoCentavos,
          efectivoContadoCentavos: d.sesion.efectivoContadoCentavos,
          efectivoEsperadoCentavos: d.sesion.efectivoEsperadoCentavos,
          diferenciaCentavos: d.sesion.diferenciaCentavos,
          mpContadoCentavos: d.sesion.mpContadoCentavos,
          mpEsperadoCentavos: d.sesion.mpEsperadoCentavos,
          mpDiferenciaCentavos: d.sesion.mpDiferenciaCentavos,
          lataContadoCentavos: d.sesion.lataContadoCentavos,
          lataFinalCentavos: d.sesion.lataFinalCentavos,
          lataDiferenciaCentavos: d.sesion.lataDiferenciaCentavos,
        ),
    ];
  }

  /// Mismo criterio que `_pendientesHistoricosDesdeBody` del servidor
  /// (Regla 3) — la única diferencia es que acá no hay JSON de por medio:
  /// [VentaHistoricaPendienteCompanion.lineas] ya son `LineaVenta` de
  /// dominio. `config`/medios se resuelven una sola vez para TODA la lista
  /// (el que llama los pasa), no una vez por venta.
  Future<repo_carga_historica.VentaHistoricaPendiente> _pendienteDesdeCompanion(
    VentaHistoricaPendienteCompanion v, {
    required ConfiguracionNegocio config,
    required MedioDePago medioEfectivo,
    required MedioDePago medioVirtual,
  }) async {
    final medio = composicionPagoDesdeTexto(v.medio);
    final resultado = await repo_ventas.calcularResultadoVenta(
      db,
      lineas: v.lineas,
      medio: medio,
      configuracionNegocio: config,
    );
    final pagos = await repo_ventas.pagosSegunMedio(
      db,
      medio: medio,
      totalCentavos: resultado.totalCentavos,
      montoEfectivoMixtoCentavos: v.montoEfectivoMixtoCentavos,
      medioEfectivoResuelto: medioEfectivo,
      medioVirtualResuelto: medioVirtual,
    );
    return repo_carga_historica.VentaHistoricaPendiente(
      venta: Venta(lineas: v.lineas),
      resultado: resultado,
      pagos: pagos,
    );
  }

  Future<List<repo_carga_historica.VentaHistoricaPendiente>> _pendientesDesdeCompanion(
    List<VentaHistoricaPendienteCompanion> ventas,
  ) async {
    final config = await repo_configuracion.configuracionNegocioActual(db);
    final medioEfectivo = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(true))).getSingle();
    final medioVirtual = await (db.select(
      db.mediosDePago,
    )..where((m) => m.esEfectivo.equals(false))).getSingle();
    return [
      for (final v in ventas)
        await _pendienteDesdeCompanion(
          v,
          config: config,
          medioEfectivo: medioEfectivo,
          medioVirtual: medioVirtual,
        ),
    ];
  }

  @override
  Future<int> guardarDiaHistorico({
    required DateTime fecha,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) async {
    final pendientes = await _pendientesDesdeCompanion(ventas);
    return repo_carga_historica.cargarDiaHistoricoDesdeVentas(
      db,
      fecha: fecha,
      usuarioId: usuarioId,
      ventas: pendientes,
    );
  }

  @override
  Future<List<DiaHistoricoCompanion>> diasHistoricos() async {
    final dias = await repo_carga_historica.listarDiasHistoricos(db);
    return [
      for (final d in dias)
        DiaHistoricoCompanion(
          sesionId: d.sesionId,
          fecha: d.fecha,
          totalCentavos: d.totalCentavos,
          cantidadVentas: d.cantidadVentas,
        ),
    ];
  }

  @override
  Future<List<VentaHistoricaResumenCompanion>> ventasDeDiaHistorico(int sesionId) async {
    final ventas = await repo_carga_historica.ventasDeDiaHistorico(db, sesionId);
    return [
      for (final v in ventas)
        VentaHistoricaResumenCompanion(
          ventaId: v.ventaId,
          totalCentavos: v.totalCentavos,
          medioResumen: v.medioResumen,
          detalle: v.detalle,
        ),
    ];
  }

  @override
  Future<ResumenDiaHistoricoCompanion> resumenDiaHistorico(int sesionId) async {
    final resumen = await repo_carga_historica.resumenDiaHistorico(db, sesionId);
    return _resumenDesdeDominio(resumen);
  }

  @override
  Future<void> agregarVentasADiaHistorico({
    required int sesionId,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) async {
    final pendientes = await _pendientesDesdeCompanion(ventas);
    await repo_carga_historica.agregarVentasADiaHistorico(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      ventas: pendientes,
    );
  }

  @override
  Future<void> eliminarVentaHistorica({
    required int sesionId,
    required int ventaId,
    required int usuarioId,
  }) => repo_carga_historica.eliminarVentaHistorica(db, ventaId: ventaId, usuarioId: usuarioId);

  @override
  Future<void> eliminarDiaHistorico(int sesionId) =>
      repo_carga_historica.eliminarDiaHistorico(db, sesionId: sesionId);

  @override
  Future<int> abrirSesion({
    required int usuarioId,
    required int fondoInicialCentavos,
    int? mpInicialCentavos,
  }) {
    return repo_ventas.abrirSesion(
      db,
      usuarioId: usuarioId,
      fondoInicialCentavos: fondoInicialCentavos,
      mpInicialCentavos: mpInicialCentavos,
    );
  }

  repo_gastos.MedioGasto _medioGastoDesde(MedioGastoCompanion medio) => switch (medio) {
    MedioGastoCompanion.cajonNormal => repo_gastos.MedioGasto.cajonNormal,
    MedioGastoCompanion.lata => repo_gastos.MedioGasto.lata,
    MedioGastoCompanion.mercadoPago => repo_gastos.MedioGasto.mercadoPago,
  };

  /// La cuenta corriente con proveedores, en la base del celular (El dueño, 2026-10-07: "seguí con pagar proveedor sin la PC"). Desde
  /// la v61 `movimientos_deuda` viaja por la sync: lo que se paga acá llega a la PC, y el pago desde una caja deja su movimiento de caja
  /// como cualquier gasto. Mismo camino (`pagarDeuda`) y mismas validaciones que `POST /proveedores/<id>/pagos` del servidor de la PC.
  @override
  Future<Map<int, int>> saldosProveedores() => repo_deuda.saldosDeuda(db);

  @override
  Future<int> pagarProveedor({
    required int proveedorId,
    required int usuarioId,
    required int montoCentavos,
    required String origen,
    int? sesionCajaId,
    String? nota,
  }) async {
    final desde = repo_deuda.OrigenPagoDeuda.desde(origen);
    try {
      // Un pago desde una caja que ya se cerró (en otro equipo, por la sync) no se graba en esa sesión.
      if (desde != repo_deuda.OrigenPagoDeuda.fuera && sesionCajaId != null) {
        await repo_ventas.verificarSesionAbierta(db, sesionCajaId);
      }
      return await repo_deuda.pagarDeuda(
        db,
        proveedorId: proveedorId,
        montoCentavos: montoCentavos,
        origen: desde,
        nota: nota,
        usuarioId: usuarioId,
        sesionCajaId: sesionCajaId,
      );
    } on repo_ventas.SesionCerradaException {
      throw const ErrorCompanion(409, 'La caja ya se cerró, este pago no se guardó');
    } on repo_deuda.SinCajaAbiertaException {
      throw const ErrorCompanion(409, 'Hace falta una caja abierta para pagar desde la caja');
    } on ArgumentError catch (e) {
      throw ErrorCompanion(400, '${e.message}');
    }
  }

  @override
  Future<int> registrarGasto({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) {
    return repo_gastos.registrarGastoRapido(
      db,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: montoCentavos,
      medio: _medioGastoDesde(medio),
      motivo: motivo,
    );
  }

  @override
  Future<int> registrarIngreso({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) {
    return repo_ingresos.registrarIngresoRapido(
      db,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: montoCentavos,
      medio: _medioGastoDesde(medio),
      motivo: motivo,
    );
  }

  /// Mismo criterio que `GET /ventas/buscar` del servidor: "Varios" no entra
  /// en esta primera versión (decisión de el dueño) — `tieneStock` ya lo trata
  /// como que siempre tiene stock, así que sin este filtro aparecería igual.
  @override
  Future<({int? gramos, List<ProductoCompanion> resultados})> buscarVenta(
    String texto, {
    bool exigirStock = true,
  }) async {
    // Una promo muestra el stock que alcanza con sus artículos: sin eso figuraba en 0 y no aparecía nunca.
    final catalogo = await repo_promos.catalogoConStockDePromos(db);
    final consulta = busqueda.interpretarTexto(texto);
    final resultados = busqueda
        .buscarProductos(catalogo: catalogo, textoBuscado: texto, exigirStock: exigirStock)
        .where((p) => !p.esVarios)
        .toList();
    return (
      gramos: consulta.gramos,
      resultados: [for (final p in resultados) _productoDesdeFila(p)],
    );
  }

  @override
  Future<ResultadoTotalVenta> calcularVenta({
    required List<LineaVenta> lineas,
    required String medio,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  }) {
    return repo_ventas.calcularResultadoVenta(
      db,
      lineas: lineas,
      medio: composicionPagoDesdeTexto(medio),
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
    );
  }

  @override
  Future<({int ventaId, int totalCentavos})> cobrarEfectivo({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
  }) {
    return repo_ventas.registrarVentaSegunMedio(
      db,
      lineas: lineas,
      medio: composicionPagoDesdeTexto('efectivo'),
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
      encargueId: encargueId,
    );
  }

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
    int? montoEfectivoMixtoCentavos,
  }) {
    return _registrarVirtualOMixto(
      lineas: lineas,
      canal: canal,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
      encargueId: encargueId,
      montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
    );
  }

  /// Venta por Mercado Pago, o mixta si viene la parte en efectivo. Un mixto que no cierra vuelve como [ErrorCompanion]
  /// con el mensaje para quien cobra.
  Future<({int ventaId, int totalCentavos})> _registrarVirtualOMixto({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    int? ordenCobroPendienteId,
    int? montoEfectivoMixtoCentavos,
  }) async {
    try {
      return await repo_ventas.registrarVentaSegunMedio(
        db,
        lineas: lineas,
        medio: montoEfectivoMixtoCentavos == null ? ComposicionPago.virtual : ComposicionPago.mixto,
        canal: canal,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        tipoDescuento: tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: encargueId,
        ordenCobroPendienteId: ordenCobroPendienteId,
        montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
      );
    } on repo_ventas.MixtoInvalido catch (e) {
      throw ErrorCompanion(400, e.mensaje);
    }
  }

  /// Por dónde cobra el celular a la terminal Point cuando no está con la PC: por el servidor de Nodo Sur, con la cuenta
  /// de Mercado Pago que el negocio conectó (el token nunca baja al celular). Sin cuenta vinculada, o con el negocio sin
  /// conectar o sin terminal elegida, se dice qué falta (`servicios/pasarela_point_nube.dart`).
  @override
  Future<OpcionesFaltanteCompanion?> opcionesFaltante() async {
    final umbral = (await db.select(db.configuracionTabla).getSingle()).umbralFaltanteCentavos;
    final fijos = await (db.select(db.gastosFijos)..where((g) => g.activo.equals(true))).get();
    return (umbralCentavos: umbral, fijos: [for (final f in fijos) (id: f.id, nombre: f.nombre)]);
  }

  @override
  Future<void> anotarFaltante({
    required int usuarioId,
    required CajaDelCierre caja,
    required int montoCentavos,
    required DestinoFaltante destino,
    int? proveedorId,
    int? gastoFijoId,
    String? nota,
  }) async {
    final sesion = await repo_ventas.sesionAbierta(db);
    if (sesion == null) throw const ErrorCompanion(409, 'No hay caja abierta');
    try {
      await repo_faltantes.anotarFaltante(
        db,
        sesionCajaId: sesion.id,
        usuarioId: usuarioId,
        caja: caja,
        montoCentavos: montoCentavos,
        destino: destino,
        proveedorId: proveedorId,
        gastoFijoId: gastoFijoId,
        nota: nota,
      );
    } on ArgumentError catch (e) {
      throw ErrorCompanion(400, '${e.message}');
    }
  }

  /// Imprime el ticket de una venta de esta base en la terminal Point, por el servidor de Nodo Sur con el Mercado Pago del
  /// negocio (El dueño, 2026-10-09: independizar el celular). Antes solo se podía con la PC, que imprime por el mismo camino.
  /// Las ventas cobradas por la PC (con el celular conectado a ella) se siguen imprimiendo por la PC: su id es el de esa base.
  Future<void> imprimirTicket(int ventaId) async {
    final sync = await syncNubeDelCelular();
    await imprimirTicketPosnet(
      ticket: await repo_ticket.ticketDeVenta(db, ventaId),
      encabezadoNegocio: (await marcaDeBase(db)).encabezadoTicketEfectivo,
      forzarNube: true,
      almacen: sync.almacen,
      cliente: sync.cliente,
    );
  }

  Future<PasarelaPoint> _pasarela() async {
    final inyectada = pasarelaDePrueba;
    if (inyectada != null) return inyectada();
    final sync = await syncNubeDelCelular();
    return elegirPasarelaPoint(
      almacen: sync.almacen,
      cliente: sync.cliente,
      mensajeSinCuenta: 'Para cobrar con la terminal sin la PC, entrá con tu cuenta y pedile al dueño que conecte Mercado Pago '
          'en horsepos.com/negocio. Mientras tanto, conectate al wifi del local o cobrá a mano.',
    );
  }

  /// Mismo criterio que `POST /ventas/posnet/iniciar` del servidor — la
  /// única diferencia real es de dónde salen las credenciales (arriba). El
  /// resto es exactamente la misma secuencia: sembrar la orden pendiente
  /// ANTES del POST a Mercado Pago (para poder reintentar sin arriesgar un
  /// doble cobro si la respuesta se pierde), después crear la orden de
  /// verdad.
  @override
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})> iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? montoEfectivoMixtoCentavos,
  }) async {
    final pasarela = await _pasarela();
    final mixto = montoEfectivoMixtoCentavos != null;
    final resultado = await repo_ventas.calcularResultadoVenta(
      db,
      lineas: lineas,
      medio: mixto ? ComposicionPago.mixto : ComposicionPago.virtual,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
    );
    // En un mixto la terminal cobra solo la parte que no se pagó en efectivo (mismo `montoParaPosnet` de la PC).
    final int montoTerminal;
    try {
      if (mixto) repo_ventas.validarEfectivoMixto(montoEfectivoMixtoCentavos, totalCentavos: resultado.totalCentavos);
      montoTerminal = resultado.totalCentavos - (montoEfectivoMixtoCentavos ?? 0);
    } on repo_ventas.MixtoInvalido catch (e) {
      throw ErrorCompanion(400, e.mensaje);
    }
    try {
      final orden = await repo_cobro.iniciarOrdenDeCobro(
        db,
        pasarela,
        sesionCajaId: sesionCajaId,
        canal: canal,
        montoCentavos: montoTerminal,
      );
      return (
        ordenPendienteId: orden.ordenPendienteId,
        ordenIdMp: orden.ordenIdMp,
        totalCentavos: resultado.totalCentavos,
      );
    } on mp.CobroPosnetException catch (e) {
      throw ErrorCompanion(502, e.mensaje);
    }
  }

  @override
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) async {
    try {
      final estado = await (await _pasarela()).consultar(ordenIdMp);
      return clasificarEstadoOrden(estado);
    } on mp.CobroPosnetException catch (e) {
      throw ErrorCompanion(502, e.mensaje);
    }
  }

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
    int? montoEfectivoMixtoCentavos,
  }) async {
    // La venta y la orden quedan ligadas en la MISMA transacción, y confirmar dos veces devuelve la misma venta.
    return _registrarVirtualOMixto(
      lineas: lineas,
      canal: canal,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
      encargueId: encargueId,
      ordenCobroPendienteId: ordenPendienteId,
      montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
    );
  }

  @override
  Future<void> resolverCobroPosnetNoAprobado({
    required int ordenPendienteId,
    required String estado,
  }) => repo_cobro.marcarOrdenResuelta(db, id: ordenPendienteId, estado: estado);

  @override
  Future<void> cancelarCobroPosnet({
    required int ordenPendienteId,
    String? ordenIdMp,
  }) async {
    if (ordenIdMp != null) {
      try {
        await (await _pasarela()).cancelar(ordenIdMp);
      } on mp.CobroPosnetException catch (e) {
        throw ErrorCompanion(502, e.mensaje);
      }
    }
    await repo_cobro.marcarOrdenResuelta(db, id: ordenPendienteId, estado: 'cancelada');
  }
}
