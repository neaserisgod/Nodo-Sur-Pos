// Interfaz común entre "hablarle a la PC por HTTP" (`ClienteCompanion`,
// hoy) y "tener la propia base local y llamar al mismo dominio directo"
// (`PuertoLocal`, companion Android sin depender del escritorio, fase 2 del
// rediseño 2026-09-15) — ver el plan completo en las notas de esa sesión.
//
// Las pantallas de `lib/companion/pantalla_*.dart` dependen de este tipo,
// nunca de `ClienteCompanion` en concreto, así que no necesitan saber si
// están hablando con la PC por red o con la base propia del celular.
//
// Arqueo se sumó acá el 2026-09-18 (Bruno: "no debería tener que escanear
// ya, es innecesario" — sacar el emparejamiento obligatorio de
// `companion_app.dart` no servía de nada si el resto de las pantallas
// seguían atadas a `ClienteCompanion` a secas). Carga histórica, historial,
// cierres y cobro por terminal Point van en camino a lo mismo; actualización
// del .apk se queda exclusiva de `ClienteCompanion` para siempre — no tiene
// sentido sin la PC, el archivo se sirve desde ahí.
//
// Los DTOs (`ProductoCompanion`, `ProveedorCompanion`, etc.) siguen siendo
// los mismos de `cliente_companion.dart` — no hace falta un tipo nuevo por
// implementación, `PuertoLocal` simplemente los arma desde las filas de
// drift en vez de parsearlos de un JSON.

import '../domain/cobro_posnet.dart' show ResultadoOrdenCobro;
import '../domain/descuento.dart' show TipoDescuento;
import '../domain/edicion_masiva_precios.dart' show CampoMonto, TipoAjustePrecio;
import '../domain/edicion_masiva_stock.dart' show TipoAjusteStock;
import '../domain/venta.dart' show LineaVenta, ResultadoTotalVenta;
import 'cliente_companion.dart';

abstract class ServicioCompanion {
  Future<List<UsuarioCompanion>> usuarios();

  Future<List<ProveedorCompanion>> proveedores();

  /// Catálogo fijo de categorías (Regla 14) — para el desplegable del alta/
  /// edición completa de producto (`PantallaFormularioProducto`). Nunca
  /// crea una categoría nueva desde acá, solo elige entre las que ya hay,
  /// mismo criterio que [proveedores].
  Future<List<CategoriaCompanion>> categorias();

  // ─── Configuración (Bruno, 2026-09-19: "que se puedan modificar las
  // reglas del negocio... desde el celular") ──────────────────────────────

  /// Recargo de cigarrillos + paso de redondeo + producto de vuelto.
  Future<ConfiguracionNegocioCompanion> configuracionNegocio();

  Future<void> actualizarRecargoCigarrillos({
    required int primerAtadoCentavos,
    required int atadoAdicionalCentavos,
    required int sueltoCentavos,
  });

  Future<void> actualizarPasoRedondeo(int montoCentavos);

  Future<void> actualizarProductoVuelto(int? productoId);

  /// Markup de referencia (Regla 14, puramente informativo) — nunca crea
  /// una categoría nueva, solo edita el % de una que ya existe.
  Future<void> actualizarMarkupCategoria(int categoriaId, int markupBp);

  Future<List<MedioDePagoCompanion>> mediosDePago();

  /// Sin alta de medios nuevos a propósito — mismo criterio que
  /// `repositorio_medios_pago.dart`: el dominio entero asume exactamente
  /// efectivo/virtual/mixto.
  Future<void> renombrarMedioPago(int id, String nombre);

  Future<void> alternarActivoMedioPago(int id, bool activo);

  /// Alta/edición de usuarios (Regla 18, catálogo de nombres para elegir al
  /// abrir caja — sin autenticación real). Devuelve el id del nuevo.
  Future<int> crearUsuarioNuevo(String nombre);

  Future<void> renombrarUsuarioExistente(int id, String nombre);

  Future<void> alternarActivoUsuarioExistente(int id, bool activo);

  /// Los cuatro `sin*` son filtros de higiene de catálogo (Bruno,
  /// 2026-09-19: "filtrar por productos sin proveedor, sin costo,
  /// etcétera") — cada uno mira una sola columna nullable del producto, ver
  /// `listarProductos` en `data/repositorio_productos.dart` (Regla 3: misma
  /// definición para las dos implementaciones de esta interfaz).
  Future<List<ProductoCompanion>> productos({
    String? busqueda,
    int? proveedorId,
    bool sinProveedor = false,
    bool sinCosto = false,
    bool sinCategoria = false,
    bool sinCodigoBarras = false,
  });

  Future<List<ProductoCompanion>> productosSinStock();

  Future<ProductoCompanion?> porCodigoBarras(String codigo);

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
  });

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
  });

  Future<void> ajustarStock(
    int productoId, {
    required int stock,
    int? stockGramos,
    String? motivo,
    required int usuarioId,
  });

  /// Editor masivo (Bruno, 2026-09-19: "editor masivo, ya sea de precios
  /// costo stock etc etc") — cuatro acciones, cada una reusando su propio
  /// repositorio en lote (`data/repositorio_productos.dart`, Regla 3: mismo
  /// camino de escritura que editar uno por uno, así el historial de
  /// precios y el rastro de stock quedan idénticos). Sin activar/desactivar
  /// en lote: no correspondía a ningún caso real de uso desde el celular
  /// (Bruno, misma fecha: "las opciones que da no se correlacionan con el
  /// editor como tal" — se había copiado del editor masivo del escritorio
  /// sin que nadie lo pidiera para acá).
  Future<void> ajustarMontoEnLote({
    required List<int> productoIds,
    required CampoMonto campo,
    required TipoAjustePrecio tipo,
    required int valor,
    required int usuarioId,
  });

  Future<void> ajustarStockEnLote({
    required List<int> productoIds,
    required TipoAjusteStock tipo,
    required int valor,
    required int usuarioId,
    String motivo = 'Ajuste masivo',
  });

  Future<void> asignarCategoriaEnLote({
    required List<int> productoIds,
    int? categoriaId,
    required int usuarioId,
  });

  Future<void> asignarProveedorEnLote({
    required List<int> productoIds,
    int? proveedorId,
    required int usuarioId,
  });

  Future<SesionCompanion> sesion();

  /// "¿Cómo vamos?" — Arqueo sin contar nada a mano (Regla 10: la
  /// diferencia de arqueo de verdad sigue siendo exclusiva del cierre real,
  /// esto no la calcula). Tira [ErrorCompanion] con status 409 si no hay
  /// caja abierta, mismo contrato que ya tenía `ClienteCompanion` contra el
  /// endpoint `/caja/estado` de la PC.
  Future<EstadoCajaCompanion> estadoCaja();

  /// Vista previa en vivo del arqueo obligatorio de 2hs — nunca guarda nada
  /// (eso es [confirmarArqueoIntermedio]), se puede llamar de nuevo cada vez
  /// que se corrige un conteo. Tira [ErrorCompanion] 409 sin caja abierta.
  Future<EstadoArqueoIntermedioCompanion> calcularArqueoIntermedio({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  });

  /// Guarda el arqueo intermedio de verdad — a diferencia de
  /// [calcularArqueoIntermedio], acá los tres conteos son obligatorios (es
  /// como el cierre, de punta a punta, en una sola confirmación).
  Future<void> confirmarArqueoIntermedio({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
  });

  /// Vista previa en vivo del cierre real (Bruno, 2026-09-19: "que deje
  /// cerrar caja desde el celular") — mismo criterio que
  /// [calcularArqueoIntermedio]: nunca guarda nada, se puede llamar de
  /// nuevo cada vez que se corrige un conteo. Tira [ErrorCompanion] 409 sin
  /// caja abierta.
  Future<ResumenCierreCompanion> calcularCierre({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  });

  /// Guarda el cierre de verdad — los tres conteos son obligatorios, mismo
  /// criterio que [confirmarArqueoIntermedio]. Tira [ErrorCompanion] 409 si
  /// la caja ya se cerró desde otro lado entre el último [calcularCierre] y
  /// esta confirmación.
  Future<void> confirmarCierre({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
    String? nota,
  });

  /// Detalle completo de un cierre YA guardado (Bruno, 2026-09-19: rework
  /// de "Cierres" con el desglose por proveedor) — mismo shape que
  /// [calcularCierre]. [sesionId] tiene que ser una sesión `CERRADA`.
  Future<ResumenCierreCompanion> detalleCierre(int sesionId);

  /// Ventas entre [desde] (inclusive) y [hasta] (exclusive), de más nueva a
  /// más vieja. [filtroMedio] null = todas.
  Future<List<VentaDelHistorialCompanion>> historialDeVentas({
    required DateTime desde,
    required DateTime hasta,
    MedioVentaHistorialCompanion? filtroMedio,
  });

  /// Solo mientras la sesión de caja de esa venta siga abierta — tira si
  /// no (Regla 6: nunca se pierde el rastro, pero anular un cierre ya
  /// arqueado lo descuadraría).
  Future<void> anularVenta({
    required int ventaId,
    required int usuarioId,
    required String motivo,
  });

  Future<DetalleVentaCompanion> detalleVenta(int ventaId);

  /// Cierres reales — excluye los días de carga histórica (esos nunca
  /// tuvieron un arqueo de verdad, Regla 6).
  Future<List<SesionCerradaCompanion>> sesionesCerradas({int limite = 30});

  /// Crea el día [fecha] con [ventas] ya armadas y lo cierra solo con
  /// arqueo automático (contado = esperado — Bruno: "es simplemente para
  /// tener un histórico"). Devuelve el `sesionId` creado.
  Future<int> guardarDiaHistorico({
    required DateTime fecha,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  });

  Future<List<DiaHistoricoCompanion>> diasHistoricos();

  Future<List<VentaHistoricaResumenCompanion>> ventasDeDiaHistorico(int sesionId);

  /// Vendido por medio de pago y por proveedor de un día ya cargado — misma
  /// fórmula que usa [estadoCaja] para la sesión de hoy (Regla 3), acá con
  /// el `sesionId` de un día distinto.
  Future<ResumenDiaHistoricoCompanion> resumenDiaHistorico(int sesionId);

  /// Agrega más ventas a un día ya cargado, sin crear una sesión nueva
  /// (Bruno: "le erré y lo cerré sin completarlo").
  Future<void> agregarVentasADiaHistorico({
    required int sesionId,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  });

  Future<void> eliminarVentaHistorica({
    required int sesionId,
    required int ventaId,
    required int usuarioId,
  });

  Future<void> eliminarDiaHistorico(int sesionId);

  /// "Cobrar a mano" — graba la venta directo, sin pasar por el ciclo de
  /// Point, conservando el canal elegido como dato informativo (Regla 3:
  /// misma fórmula que `cobrarEfectivo`, con medio virtual).
  Future<({int ventaId, int totalCentavos})> cobrarVirtualAMano({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    required String canal,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  });

  /// Crea la orden en la terminal Point — `canal`: `'qr'` | `'debit_card'`.
  /// Tira [ErrorCompanion] si no hay credenciales de cobro configuradas
  /// (mismo mensaje que el escritorio).
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})> iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  });

  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp);

  /// El pago se aprobó: recién acá se graba la venta real. [tipoDescuento]/
  /// [valorDescuento] tienen que ser los MISMOS que [iniciarCobroPosnet].
  Future<({int ventaId, int totalCentavos})> confirmarCobroPosnet({
    required int ordenPendienteId,
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  });

  Future<void> resolverCobroPosnetNoAprobado({
    required int ordenPendienteId,
    required String estado,
  });

  Future<void> cancelarCobroPosnet({
    required int ordenPendienteId,
    String? ordenIdMp,
  });

  Future<int> abrirSesion({
    required int usuarioId,
    required int fondoInicialCentavos,
  });

  Future<int> registrarGasto({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  });

  Future<int> registrarIngreso({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  });

  Future<({int? gramos, List<ProductoCompanion> resultados})> buscarVenta(
    String texto, {
    bool exigirStock = true,
  });

  Future<ResultadoTotalVenta> calcularVenta({
    required List<LineaVenta> lineas,
    required String medio,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  });

  Future<({int ventaId, int totalCentavos})> cobrarEfectivo({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  });
}
