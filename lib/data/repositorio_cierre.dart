// Cierre de caja (fase 4). Junta los agregados del día y se los pasa tal
// cual a las funciones de dominio ya escritas en la fase 1
// (lib/domain/caja.dart, reposicion.dart) — acá no vive ninguna fórmula de
// negocio nueva, solo las consultas que las alimentan.

import 'package:drift/drift.dart';

import '../domain/caja.dart';
import '../domain/equilibrio.dart';
import '../domain/reposicion.dart';
import 'database.dart';
import 'linea_venta_reconstruccion.dart';
import 'repositorio_equilibrio.dart';
import 'repositorio_ventas_abiertas.dart';

export 'repositorio_ventas_abiertas.dart' show VentasAbiertasPendientesException;

Future<Caja> _cajaNormal(AppDatabase db) =>
    (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();

Future<Caja> _cajaLata(AppDatabase db) =>
    (db.select(db.cajas)..where((c) => c.esLata.equals(true))).getSingle();

Future<MedioDePago> _medioMercadoPago(AppDatabase db) =>
    (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();

/// 'GASTO', 'PAGO_PROVEEDOR' y 'RETIRO' son, para el arqueo, el mismo tipo
/// de evento: plata que sale de una caja. Un pago a proveedor o un retiro
/// que solo contaran como 'GASTO' en el filtro dejarían el monto afuera de
/// la caja esperada — exactamente el agujero que encontró el dueño
/// (`DECISIONES.md`, para 'PAGO_PROVEEDOR'; mismo motivo para 'RETIRO',
/// Regla 13) — así que toda función que suma egresos por caja usa esta
/// misma lista, en vez de filtrar 'GASTO' sola cada una por su cuenta
/// (Regla 3).
const tiposEgresoDeCaja = ['GASTO', 'PAGO_PROVEEDOR', 'RETIRO'];

Future<int> _sumaMovimientos(
  AppDatabase db, {
  required int sesionId,
  required int cajaId,
  required List<String> tipos,
  Expression<bool>? filtroExtra,
}) async {
  final query = db.selectOnly(db.movimientosDeCaja)
    ..addColumns([db.movimientosDeCaja.montoCentavos.sum()])
    ..where(
      db.movimientosDeCaja.sesionCajaId.equals(sesionId) &
          db.movimientosDeCaja.cajaId.equals(cajaId) &
          db.movimientosDeCaja.tipo.isIn(tipos),
    );
  if (filtroExtra != null) query.where(filtroExtra);
  final fila = await query.getSingle();
  return fila.read(db.movimientosDeCaja.montoCentavos.sum()) ?? 0;
}

/// Efectivo de ventas del día, para la fórmula de caja esperada (Regla 10):
/// todas las ventas cobradas en efectivo, cigarrillos incluidos — la
/// separación no participa de este número.
///
/// [cajaNormal] es un parámetro opcional para que un llamador que ya
/// resolvió la fila (`calcularResumenCierre`/`estadoCajaEnVivo`, que llaman
/// a varias de estas funciones juntas) no la vuelva a consultar — sin él,
/// se resuelve acá mismo como siempre, así que ningún llamador existente
/// tiene que cambiar.
Future<int> efectivoDeVentasDelDia(
  AppDatabase db,
  int sesionId, {
  Caja? cajaNormal,
}) async {
  final caja = cajaNormal ?? await _cajaNormal(db);
  return _sumaMovimientos(db, sesionId: sesionId, cajaId: caja.id, tipos: const ['VENTA']);
}

/// Gastos en efectivo con origen "cajón normal" (gasto rápido de la fase 3).
///
/// Excluye los gastos marcados con `medioPagoId` = Mercado Pago (El dueño,
/// sesión del 31/08/2026): esos no salieron del cajón, aunque por ahora
/// tengan que quedar con `cajaId = cajaNormal` (MP no es una fila de
/// `Cajas`) — hay que filtrar por medio de pago, no solo por caja, o un
/// gasto pagado con MP se restaría dos veces (acá y en `gastosPorMpDelDia`).
/// Incluye `PAGO_PROVEEDOR` (ver `tiposEgresoDeCaja`): un pago a proveedor en
/// efectivo sale del cajón igual que un gasto — si no se restara acá, el
/// arqueo marcaría un faltante por ese monto.
Future<int> gastosEnEfectivoDelDia(
  AppDatabase db,
  int sesionId, {
  Caja? cajaNormal,
  MedioDePago? medioMercadoPago,
}) async {
  final caja = cajaNormal ?? await _cajaNormal(db);
  final mp = medioMercadoPago ?? await _medioMercadoPago(db);
  return _sumaMovimientos(
    db,
    sesionId: sesionId,
    cajaId: caja.id,
    tipos: tiposEgresoDeCaja,
    filtroExtra: db.movimientosDeCaja.medioPagoId.equals(mp.id).not() |
        db.movimientosDeCaja.medioPagoId.isNull(),
  );
}

/// Gastos pagados con Mercado Pago (fase de MP como caja más): se restan de
/// lo cobrado por medios no efectivo para llegar al "MP esperado" del día.
/// Incluye pagos a proveedor por Mercado Pago (`tiposEgresoDeCaja`): esa plata
/// sale del saldo de MP igual que un gasto pagado con MP.
Future<int> gastosPorMpDelDia(
  AppDatabase db,
  int sesionId, {
  Caja? cajaNormal,
  MedioDePago? medioMercadoPago,
}) async {
  final caja = cajaNormal ?? await _cajaNormal(db);
  final mp = medioMercadoPago ?? await _medioMercadoPago(db);
  return _sumaMovimientos(
    db,
    sesionId: sesionId,
    cajaId: caja.id,
    tipos: tiposEgresoDeCaja,
    filtroExtra: db.movimientosDeCaja.medioPagoId.equals(mp.id),
  );
}

/// Gastos con origen "lata de cigarrillos": en la práctica, pagos a Distribuidora
/// Cigarros. Se restan del saldo final de la lata — si no se restaran, la
/// lata mostraría un número inflado desde el primer pago que se le hiciera.
/// Incluye `PAGO_PROVEEDOR` (`tiposEgresoDeCaja`) por las dudas, aunque hoy
/// `pagarProveedor` nunca graba con `cajaId = cajaLata` — Distribuidora de Cigarrillos se
/// paga desde el gasto rápido con origen lata, no desde este flujo nuevo.
Future<int> pagosALataDelDia(AppDatabase db, int sesionId) async {
  final cajaLata = await _cajaLata(db);
  return _sumaMovimientos(db, sesionId: sesionId, cajaId: cajaLata.id, tipos: tiposEgresoDeCaja);
}

// ─── Ingreso rápido (El dueño, 2026-09-13) ──────────────────────────────────
// Espejo de los tres de arriba, pero para plata que ENTRA sin ser venta —
// mismo criterio de "una caja física, un filtro por medioPagoId cuando
// corresponde", tipo 'INGRESO' en vez de la lista `tiposEgresoDeCaja` (acá
// no hay 'PAGO_PROVEEDOR'/'RETIRO' que compartan el mismo significado: un
// ingreso rápido es su propio tipo, sin variantes).

/// Ingresos en efectivo con origen "cajón normal" — mismo filtro por
/// `medioPagoId` que `gastosEnEfectivoDelDia`, mismo motivo: un ingreso
/// pagado "por Mercado Pago" (poco común, pero la caja está disponible) no
/// entró al cajón físico.
Future<int> ingresosEnEfectivoDelDia(
  AppDatabase db,
  int sesionId, {
  Caja? cajaNormal,
  MedioDePago? medioMercadoPago,
}) async {
  final caja = cajaNormal ?? await _cajaNormal(db);
  final mp = medioMercadoPago ?? await _medioMercadoPago(db);
  return _sumaMovimientos(
    db,
    sesionId: sesionId,
    cajaId: caja.id,
    tipos: const ['INGRESO'],
    filtroExtra: db.movimientosDeCaja.medioPagoId.equals(mp.id).not() |
        db.movimientosDeCaja.medioPagoId.isNull(),
  );
}

/// Ingresos por Mercado Pago — se suman a lo cobrado por medios no efectivo
/// para el "MP esperado" del día.
Future<int> ingresosPorMpDelDia(
  AppDatabase db,
  int sesionId, {
  Caja? cajaNormal,
  MedioDePago? medioMercadoPago,
}) async {
  final caja = cajaNormal ?? await _cajaNormal(db);
  final mp = medioMercadoPago ?? await _medioMercadoPago(db);
  return _sumaMovimientos(
    db,
    sesionId: sesionId,
    cajaId: caja.id,
    tipos: const ['INGRESO'],
    filtroExtra: db.movimientosDeCaja.medioPagoId.equals(mp.id),
  );
}

/// Ingresos con origen "lata de cigarrillos" — se suman al saldo final de
/// la lata.
Future<int> ingresosALaLataDelDia(AppDatabase db, int sesionId) async {
  final cajaLata = await _cajaLata(db);
  return _sumaMovimientos(db, sesionId: sesionId, cajaId: cajaLata.id, tipos: const ['INGRESO']);
}

/// Lo cobrado por medios no efectivo (Mercado Pago) en las ventas de la
/// sesión — la mitad "ingreso" de la fórmula de MP esperado
/// (`mpEsperadoCentavos`, `lib/domain/caja.dart`). Sale de `Pagos`, no de
/// `movimientos_de_caja`: un pago virtual nunca generó movimiento de caja
/// (Regla de la fase 3), así que esta es la única fuente que ya existe para
/// este dato sin tocar el camino crítico de cobro.
///
/// Excluye ventas anuladas (El dueño, 2026-09-13, bug real: "no toma en cuenta
/// la anulación"): `anularVenta` revierte el efectivo con un movimiento de
/// caja negativo (Regla 6, el ledger nunca se toca ni se borra), pero un
/// pago virtual nunca tuvo movimiento de caja que revertir — sin este
/// filtro, el pago de una venta por Mercado Pago ya anulada seguía
/// sumando al esperado de MP para siempre.
Future<int> pagosNoEfectivoDelDia(
  AppDatabase db,
  int sesionId, {
  MedioDePago? medioMercadoPago,
}) async {
  final mp = medioMercadoPago ?? await _medioMercadoPago(db);
  final query = db.selectOnly(db.pagos)
    ..addColumns([db.pagos.montoCentavos.sum()])
    ..join([innerJoin(db.ventas, db.ventas.id.equalsExp(db.pagos.ventaId))])
    ..where(
      db.ventas.sesionCajaId.equals(sesionId) &
          db.pagos.medioPagoId.equals(mp.id) &
          db.ventas.anuladaEn.isNull(),
    );
  final fila = await query.getSingle();
  return fila.read(db.pagos.montoCentavos.sum()) ?? 0;
}

/// Suma del redondeo de todas las ventas de la sesión (Regla 2: se muestra
/// como línea propia, separada de la diferencia de caja). Excluye
/// anuladas — mismo motivo que `pagosNoEfectivoDelDia`: el redondeo de una
/// venta que se revirtió no debería seguir apareciendo en el acumulado del
/// día.
Future<int> redondeoAcumuladoDelDia(AppDatabase db, int sesionId) async {
  final query = db.selectOnly(db.ventas)
    ..addColumns([db.ventas.redondeoCentavos.sum()])
    ..where(db.ventas.sesionCajaId.equals(sesionId) & db.ventas.anuladaEn.isNull());
  final fila = await query.getSingle();
  return fila.read(db.ventas.redondeoCentavos.sum()) ?? 0;
}

/// Precio de lista de los cigarrillos vendidos hoy (atados o sueltos), sin
/// importar el medio de pago (Regla 6) — es el monto que alimenta
/// `separarCigarrillos`. Excluye anuladas — mismo motivo que
/// `pagosNoEfectivoDelDia`: los cigarrillos de una venta revertida no se
/// separan a la lata en el cierre real.
Future<int> precioListaCigarrillosDelDia(AppDatabase db, int sesionId) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(
          db.ventas.sesionCajaId.equals(sesionId) &
              db.lineasDeVenta.tipoCigarrillo.isNotValue('ninguno') &
              db.ventas.anuladaEn.isNull(),
        ))
      .get();

  return filas.fold<int>(0, (acumulado, fila) {
    final linea = fila.readTable(db.lineasDeVenta);
    return acumulado + linea.precioUnitarioCentavos * (linea.cantidad ?? 1);
  });
}

/// Reposición del día (lib/domain/reposicion.dart), reconstruyendo las
/// líneas desde `lineas_de_venta` con el `proveedorIdFoto` guardado en cada
/// una — no hace falta volver a mirar el catálogo de productos. Excluye
/// anuladas: el stock de esas líneas ya se repuso (`anularVenta`), contarlas
/// acá pedería reponer de nuevo algo que nunca se terminó de vender.
Future<ResultadoReposicion> reposicionDelDia(AppDatabase db, int sesionId) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(db.ventas.sesionCajaId.equals(sesionId) & db.ventas.anuladaEn.isNull()))
      .get();

  final lineas = filas.map((fila) => lineaParaReposicionDesde(fila.readTable(db.lineasDeVenta), venta: fila.readTable(db.ventas))).toList();

  return calcularReposicion(lineas: lineas);
}

/// La sesión cerrada inmediatamente anterior a [sesionIdActual] — de ahí
/// sale el pendiente de cigarrillos que se arrastra (Regla 6).
Future<SesionCaja?> sesionCerradaAnterior(AppDatabase db, int sesionIdActual) {
  return (db.select(db.sesionesDeCaja)
        ..where((s) => s.estado.equals('CERRADA') & s.id.isSmallerThanValue(sesionIdActual))
        ..orderBy([(s) => OrderingTerm.desc(s.id)])
        ..limit(1))
      .getSingleOrNull();
}

/// true si [sesionId] es la sesión más reciente que existe — solo esa se
/// puede reabrir (Regla 6): un cierre de hace una semana queda cerrado para
/// siempre una vez que se abrió un día nuevo.
Future<bool> esUltimaSesion(AppDatabase db, int sesionId) async {
  final ultima = await (db.select(db.sesionesDeCaja)
        ..orderBy([(s) => OrderingTerm.desc(s.id)])
        ..limit(1))
      .getSingleOrNull();
  return ultima?.id == sesionId;
}

/// true si [fecha] no es de hoy (comparando solo año/mes/día). Se usa para
/// forzar el cierre de una sesión que quedó abierta de un día anterior
/// (Regla 5) antes de dejar abrir el día de hoy.
bool esDeOtroDia(DateTime fecha) {
  final ahora = DateTime.now();
  return fecha.year != ahora.year || fecha.month != ahora.month || fecha.day != ahora.day;
}

/// La sesión cerrada más reciente, solo si se cerró **hoy** — de acá sale
/// la precarga del turno entrante (El dueño, sesión del 31/08/2026): "QUEDA EN
/// EL CAJON" de la hoja que se cierra es la "Caja inicial NORMAL" de la que
/// se abre, para no hacer contar dos veces la misma plata en el mismo
/// cambio de manos. Si la última cerrada fue de un día anterior, esto
/// devuelve `null` — la primera apertura del día arranca como siempre, sin
/// precarga.
Future<SesionCaja?> sesionCerradaHoyParaPrecarga(AppDatabase db) async {
  final ultimaCerrada = await (db.select(db.sesionesDeCaja)
        ..where((s) => s.estado.equals('CERRADA'))
        ..orderBy([(s) => OrderingTerm.desc(s.fechaCierre)])
        ..limit(1))
      .getSingleOrNull();
  final fechaCierre = ultimaCerrada?.fechaCierre;
  if (fechaCierre == null || esDeOtroDia(fechaCierre)) return null;
  return ultimaCerrada;
}

/// El monto a sugerir para "Fondo inicial (caja normal)" de la próxima
/// apertura — `null` si no hay nada que sugerir (primera apertura del día,
/// arranca vacío como siempre). Extraída de `dialogo_apertura_caja.dart`
/// (spike companion app, 2026-09-07): la apertura de emergencia desde el
/// celular necesita la misma sugerencia, y Regla 3 pide un solo lugar para
/// esta cuenta, no una copia en el servidor.
Future<int?> fondoInicialSugeridoCentavos(AppDatabase db) async {
  final anterior = await sesionCerradaHoyParaPrecarga(db);
  if (anterior == null) return null;
  return quedaEnCajonCentavos(
    efectivoContadoCentavos: anterior.efectivoContadoCentavos ?? 0,
    lataSeparadoCentavos: anterior.lataSeparadoCentavos ?? 0,
  );
}

/// Cantidad de ventas de la sesión — `resumenDiaHistorico` ya trae el
/// total y el desglose por medio/proveedor, pero no un conteo; se pide
/// aparte solo donde hace falta mostrarlo.
Future<int> cantidadVentasDelDia(AppDatabase db, int sesionId) async {
  final query = db.selectOnly(db.ventas)
    ..addColumns([db.ventas.id.count()])
    ..where(db.ventas.sesionCajaId.equals(sesionId));
  final fila = await query.getSingle();
  return fila.read(db.ventas.id.count()) ?? 0;
}

class EstadoCajaEnVivo {
  final int efectivoEsperadoCentavos;
  final int mpEsperadoCentavos;

  /// Ya incluido dentro de [efectivoEsperadoCentavos] (Regla 2: efectivo
  /// redondea) — se expone aparte para que un consumidor (la companion,
  /// hoy) pueda mostrarlo como línea propia en vez de dejarlo mezclado en
  /// el total, mismo motivo que ya aplica el cierre real
  /// (`ResumenCierre.redondeoAcumuladoCentavos`): sin esto se confunde con
  /// un descuadre de caja.
  final int redondeoAcumuladoCentavos;

  /// La lata que se arrastra de ANTES de hoy (no cambia con las ventas del
  /// día — eso solo se sabe al cerrar de verdad, Regla 10: la separación
  /// depende de cuánto efectivo se contó, algo que este chequeo en vivo no
  /// pide). Se expone para que se vea que existe una segunda caja además
  /// de la normal, aunque su valor de hoy todavía no esté definido.
  final int lataInicialCentavos;

  const EstadoCajaEnVivo({
    required this.efectivoEsperadoCentavos,
    required this.mpEsperadoCentavos,
    required this.redondeoAcumuladoCentavos,
    required this.lataInicialCentavos,
  });
}

/// "¿Cómo vamos?" en cualquier momento del día, sin contar nada a mano
/// (El dueño, 2026-09-07: "un botón de arqueo... para saber que tal vamos en
/// cualquier momento sin tener que contar a mano las ventas del día") —
/// primera mitad de `calcularResumenCierre`, las mismas fórmulas
/// (`cajaEsperadaCentavos`/`mpEsperadoCentavos`) pero sin el contado: por
/// eso no hay `diferenciaArqueo` acá (esa sí necesita plata contada) ni
/// separación de cigarrillos (Regla 10: primero se cuenta, después se
/// compara y se separa — eso pasa solo en el cierre de verdad).
Future<EstadoCajaEnVivo> estadoCajaEnVivo(AppDatabase db, int sesionId) async {
  final sesion =
      await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  // `_cajaNormal`/`_medioMercadoPago` son tablas de 2 filas que las cuatro
  // consultas de abajo necesitaban resolver cada una por su cuenta — se
  // resuelven una sola vez acá y se pasan, en vez de volver a preguntar.
  final cajaNormal = await _cajaNormal(db);
  final mp = await _medioMercadoPago(db);

  final resultados = await Future.wait([
    efectivoDeVentasDelDia(db, sesionId, cajaNormal: cajaNormal),
    gastosEnEfectivoDelDia(db, sesionId, cajaNormal: cajaNormal, medioMercadoPago: mp),
    ingresosEnEfectivoDelDia(db, sesionId, cajaNormal: cajaNormal, medioMercadoPago: mp),
    redondeoAcumuladoDelDia(db, sesionId),
    pagosNoEfectivoDelDia(db, sesionId, medioMercadoPago: mp),
    gastosPorMpDelDia(db, sesionId, cajaNormal: cajaNormal, medioMercadoPago: mp),
    ingresosPorMpDelDia(db, sesionId, cajaNormal: cajaNormal, medioMercadoPago: mp),
  ]);
  final [
    efectivoDeVentas,
    gastosEnEfectivo,
    ingresosEnEfectivo,
    redondeo,
    pagosNoEfectivo,
    gastosPorMp,
    ingresosPorMp,
  ] = resultados;

  final efectivoEsperado = cajaEsperadaCentavos(
    inicialCentavos: sesion.fondoInicialCentavos,
    efectivoDeVentasCentavos: efectivoDeVentas,
    gastosEnEfectivoCentavos: gastosEnEfectivo,
    ingresosEnEfectivoCentavos: ingresosEnEfectivo,
  );
  final mpEsperado = mpEsperadoCentavos(
    inicialCentavos: sesion.saldoMpInicialCentavos,
    pagosNoEfectivoCentavos: pagosNoEfectivo,
    gastosPorMpCentavos: gastosPorMp,
    ingresosPorMpCentavos: ingresosPorMp,
  );

  return EstadoCajaEnVivo(
    efectivoEsperadoCentavos: efectivoEsperado,
    mpEsperadoCentavos: mpEsperado,
    redondeoAcumuladoCentavos: redondeo,
    lataInicialCentavos: sesion.lataInicialCentavos,
  );
}

class ResumenCierre {
  final int efectivoEsperadoCentavos;
  final int diferenciaCentavos;
  final ResultadoSeparacionCigarrillos separacionCigarrillos;
  final int lataFinalCentavos;
  final int redondeoAcumuladoCentavos;

  /// Reposición del día completa (`lib/domain/reposicion.dart`) — no solo
  /// el total sin costo, también el desglose por proveedor
  /// (`costoRealPorProveedorCentavos`/`vendidoPorProveedorCentavos`/
  /// `gananciaPorProveedorCentavos`) que ya calculaba `reposicionDelDia`
  /// pero antes se tiraba: la companion lo necesita para el detalle de un
  /// cierre (El dueño, 2026-09-19: "lo que se debe separar por cada
  /// proveedor"). [vendidoSinCostoCentavos] queda como atajo de
  /// conveniencia para no tocar los llamadores que ya lo usaban.
  final ResultadoReposicion reposicion;

  int get vendidoSinCostoCentavos => reposicion.vendidoSinCostoCentavos;

  /// Null si falta cargar el monto de algún concepto de fijos este mes
  /// (fase 7, `repositorio_equilibrio.dart`) — un indicador inventado sería
  /// peor que no mostrar nada.
  final int? reservaDiariaFijosCentavos;

  /// Siempre calculable (a diferencia del efectivo, no depende de ningún
  /// contado): el inicial de MP ya se fijó al abrir la sesión
  /// (`saldoMpInicialCentavos`, 2026-09-12), no hace falta preguntarlo acá.
  final int mpEsperadoCentavos;

  /// Null hasta que se escribe el MP contado (Regla 1/2: la diferencia no
  /// se ve hasta confirmar lo contado, vale igual para MP).
  final int? mpDiferenciaCentavos;

  /// Null hasta que se escribe la lata contada — mismo criterio que
  /// [mpDiferenciaCentavos], la lata se arquea como una caja de verdad
  /// (ítem 3): [lataFinalCentavos] es lo esperado, esta es la diferencia
  /// contra lo que el dueño contó de verdad.
  final int? lataDiferenciaCentavos;

  /// De qué sale [efectivoEsperadoCentavos] (`cajaEsperadaCentavos`): el
  /// cierre lo muestra renglón por renglón ("Lenguaje de diseño", mock
  /// `CierreCaja`), así la diferencia se entiende sin hacer cuentas. Null
  /// solo en resúmenes armados a mano (tests viejos).
  final ({int fondo, int ventas, int gastos, int ingresos, int redondeo})? desgloseEfectivo;

  const ResumenCierre({
    required this.efectivoEsperadoCentavos,
    required this.diferenciaCentavos,
    required this.separacionCigarrillos,
    required this.lataFinalCentavos,
    required this.redondeoAcumuladoCentavos,
    required this.reposicion,
    required this.reservaDiariaFijosCentavos,
    required this.mpEsperadoCentavos,
    required this.mpDiferenciaCentavos,
    required this.lataDiferenciaCentavos,
    this.desgloseEfectivo,
  });
}

/// Calcula todo lo que hace falta mostrar (y guardar) al cerrar, a partir
/// del efectivo ya contado. Es la ÚNICA función que arma este cálculo:
/// `cerrarSesion` la llama para saber qué persistir, y la pantalla la llama
/// de nuevo en vivo cada vez que se corrige el conteo — así la vista previa
/// y lo que termina guardado nunca pueden desalinearse (Regla 3).
Future<ResumenCierre> calcularResumenCierre(
  AppDatabase db, {
  required int sesionId,
  required int efectivoContadoCentavos,
  int? mpContadoCentavos,
  int? lataContadoCentavos,
}) async {
  final sesion =
      await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  // `cajaNormal`/`mp` se resuelven una sola vez (en paralelo entre sí) y se
  // pasan a las cuatro funciones que antes las volvían a consultar cada
  // una. El resto de las consultas de abajo son independientes entre sí
  // (ninguna depende del resultado de otra) — se lanzan todas de una,
  // sin esperar cada `await` en serie, y se recién esperan donde hace
  // falta el valor para el cálculo síncrono.
  final cajaYMedio = await Future.wait([_cajaNormal(db), _medioMercadoPago(db)]);
  final cajaNormal = cajaYMedio[0] as Caja;
  final mp = cajaYMedio[1] as MedioDePago;

  final futuroEfectivoDeVentas = efectivoDeVentasDelDia(db, sesionId, cajaNormal: cajaNormal);
  final futuroGastosEnEfectivo = gastosEnEfectivoDelDia(
    db,
    sesionId,
    cajaNormal: cajaNormal,
    medioMercadoPago: mp,
  );
  final futuroIngresosEnEfectivo = ingresosEnEfectivoDelDia(
    db,
    sesionId,
    cajaNormal: cajaNormal,
    medioMercadoPago: mp,
  );
  final futuroRedondeo = redondeoAcumuladoDelDia(db, sesionId);
  final futuroPrecioListaCigarrillos = precioListaCigarrillosDelDia(db, sesionId);
  final futuroAnterior = sesionCerradaAnterior(db, sesionId);
  final futuroPagosLata = pagosALataDelDia(db, sesionId);
  final futuroIngresosALata = ingresosALaLataDelDia(db, sesionId);
  final futuroPagosNoEfectivo = pagosNoEfectivoDelDia(db, sesionId, medioMercadoPago: mp);
  final futuroGastosPorMp = gastosPorMpDelDia(
    db,
    sesionId,
    cajaNormal: cajaNormal,
    medioMercadoPago: mp,
  );
  final futuroIngresosPorMp = ingresosPorMpDelDia(
    db,
    sesionId,
    cajaNormal: cajaNormal,
    medioMercadoPago: mp,
  );
  final futuroReposicion = reposicionDelDia(db, sesionId);
  final futuroFijos = fijosDelMes(db, mesAnioDe(sesion.fechaApertura));

  final redondeo = await futuroRedondeo;
  final ventasEfectivo = await futuroEfectivoDeVentas;
  final gastosEfectivo = await futuroGastosEnEfectivo;
  final ingresosEfectivo = await futuroIngresosEnEfectivo;
  final esperada = cajaEsperadaCentavos(
    inicialCentavos: sesion.fondoInicialCentavos,
    efectivoDeVentasCentavos: ventasEfectivo,
    gastosEnEfectivoCentavos: gastosEfectivo,
    ingresosEnEfectivoCentavos: ingresosEfectivo,
  );
  final diferencia =
      diferenciaArqueo(contadoCentavos: efectivoContadoCentavos, esperadoCentavos: esperada);

  final anterior = await futuroAnterior;
  final separacion = separarCigarrillos(
    efectivoContadoCentavos: efectivoContadoCentavos,
    precioListaCigarrillosVendidosHoyCentavos: await futuroPrecioListaCigarrillos,
    pendienteDeCierresAnterioresCentavos: anterior?.lataPendienteCentavos ?? 0,
  );

  final lataFinal = lataNuevaCentavos(
    lataInicialCentavos: sesion.lataInicialCentavos,
    separadoHoyCentavos: separacion.separadoCentavos,
    pagosAProveedorDesdeLataCentavos: await futuroPagosLata,
    ingresosALaLataCentavos: await futuroIngresosALata,
  );
  final lataDiferencia = lataContadoCentavos == null
      ? null
      : diferenciaArqueo(contadoCentavos: lataContadoCentavos, esperadoCentavos: lataFinal);

  final mpEsperada = mpEsperadoCentavos(
    inicialCentavos: sesion.saldoMpInicialCentavos,
    pagosNoEfectivoCentavos: await futuroPagosNoEfectivo,
    gastosPorMpCentavos: await futuroGastosPorMp,
    ingresosPorMpCentavos: await futuroIngresosPorMp,
  );
  final mpDiferencia = mpContadoCentavos == null
      ? null
      : diferenciaArqueo(contadoCentavos: mpContadoCentavos, esperadoCentavos: mpEsperada);

  final reposicion = await futuroReposicion;

  final fijos = await futuroFijos;
  final reservaDiaria = fijos.total == null
      ? null
      : reservaDiariaFijosCentavos(
          fijosMensualesCentavos: fijos.total!,
          diasDelMes: DateTime(sesion.fechaApertura.year, sesion.fechaApertura.month + 1, 0).day,
        );

  return ResumenCierre(
    efectivoEsperadoCentavos: esperada,
    diferenciaCentavos: diferencia,
    separacionCigarrillos: separacion,
    lataFinalCentavos: lataFinal,
    redondeoAcumuladoCentavos: redondeo,
    reposicion: reposicion,
    reservaDiariaFijosCentavos: reservaDiaria,
    mpEsperadoCentavos: mpEsperada,
    mpDiferenciaCentavos: mpDiferencia,
    lataDiferenciaCentavos: lataDiferencia,
    desgloseEfectivo: (
      fondo: sesion.fondoInicialCentavos,
      ventas: ventasEfectivo,
      gastos: gastosEfectivo,
      ingresos: ingresosEfectivo,
      redondeo: redondeo,
    ),
  );
}

/// Cierra la sesión: recalcula el resumen y lo persiste tal cual, sin
/// recalcular nada por separado (ver `calcularResumenCierre`).
///
/// [fechaCierre] default a ahora; la carga histórica (fase 9) pasa la fecha
/// real del día que se está cargando — es lo que queda guardado en la
/// sesión, pero OJO: no es lo que ordena a `sesionCerradaAnterior` (esa
/// función ordena por `id` de inserción, no por esta fecha — ver
/// TRAMPAS.md). Lo que de verdad mantiene bien el arrastre de pendiente de
/// cigarrillos entre días (Regla 6) es llamar a `cerrarSesion` para cada
/// día histórico en orden cronológico, del más viejo al más nuevo.
/// Se tira si, entre que se calculó el resumen y se intentó persistir, la
/// sesión dejó de estar `ABIERTA` (alguien más la cerró mientras tanto) —
/// El dueño, 2026-09-19: "aislar los usuarios para que no se pisen". Nunca un
/// `UPDATE` silencioso a ciegas.
class SesionYaNoAbiertaException implements Exception {
  const SesionYaNoAbiertaException(this.sesionId);
  final int sesionId;
}

Future<void> cerrarSesion(
  AppDatabase db, {
  required int sesionId,
  required int usuarioId,
  required int efectivoContadoCentavos,
  required int mpContadoCentavos,
  required int lataContadoCentavos,
  String? nota,
  DateTime? fechaCierre,
  // `false` solo para `_recalcularResumenDiaHistorico`
  // (`repositorio_carga_historica.dart`): ahí "cerrar" en realidad
  // recalcula los campos cacheados de un día histórico que YA está
  // CERRADA (al agregar/borrar una venta de un día ya cargado) — llamar
  // de nuevo sobre esa misma sesión es intencional, no un choque real
  // entre dos personas. Un cierre real (desde la pantalla de cierre, sea
  // escritorio o companion) siempre deja esto en `true`.
  bool exigirAbierta = true,
}) {
  // Todo en una sola transacción (mismo criterio que `registrarVenta`,
  // `repositorio_ventas.dart`): el cálculo del resumen y el `UPDATE` final
  // no pueden separarse — un gasto/venta que intente colarse en el medio
  // queda bloqueado por Drift hasta que esta transacción termine, así que
  // nunca queda huérfano (contado en la caja real, pero no en
  // `efectivoEsperadoCentavos`/`diferenciaCentavos` ya persistidos).
  return db.transaction(() async {
    // Una venta armada y sin cobrar no puede quedar colgando de una caja que
    // se cierra (El dueño, 2026-09-29): se cobra o se descarta antes de cerrar.
    if (exigirAbierta) {
      final abiertas = await cantidadVentasAbiertasConLineas(db, sesionId);
      if (abiertas > 0) throw VentasAbiertasPendientesException(abiertas);
    }

    final resumen = await calcularResumenCierre(
      db,
      sesionId: sesionId,
      efectivoContadoCentavos: efectivoContadoCentavos,
      mpContadoCentavos: mpContadoCentavos,
      lataContadoCentavos: lataContadoCentavos,
    );

    // `WHERE estado='ABIERTA'` además del `id` (salvo [exigirAbierta] en
    // `false`): distingue "cerré yo" de "alguien ya cerró esto" — antes el
    // `UPDATE` "tenía éxito" sin haber tocado nada si la sesión ya estaba
    // `CERRADA`.
    final filas =
        await (db.update(db.sesionesDeCaja)..where(
              (s) => exigirAbierta
                  ? s.id.equals(sesionId) & s.estado.equals('ABIERTA')
                  : s.id.equals(sesionId),
            ))
            .write(
          SesionesDeCajaCompanion(
            estado: const Value('CERRADA'),
            fechaCierre: Value(fechaCierre ?? DateTime.now()),
            usuarioCerroId: Value(usuarioId),
            efectivoContadoCentavos: Value(efectivoContadoCentavos),
            efectivoEsperadoCentavos: Value(resumen.efectivoEsperadoCentavos),
            diferenciaCentavos: Value(resumen.diferenciaCentavos),
            lataSeparadoCentavos: Value(resumen.separacionCigarrillos.separadoCentavos),
            lataPendienteCentavos: Value(resumen.separacionCigarrillos.pendienteCentavos),
            lataFinalCentavos: Value(resumen.lataFinalCentavos),
            lataContadoCentavos: Value(lataContadoCentavos),
            lataDiferenciaCentavos: Value(resumen.lataDiferenciaCentavos),
            mpContadoCentavos: Value(mpContadoCentavos),
            mpEsperadoCentavos: Value(resumen.mpEsperadoCentavos),
            mpDiferenciaCentavos: Value(resumen.mpDiferenciaCentavos),
            nota: Value(nota),
            actualizadoEn: Value(DateTime.now()),
          ),
        );

    if (exigirAbierta && filas == 0) throw SesionYaNoAbiertaException(sesionId);
  });
}

/// Reabre la sesión cerrada más reciente (Regla 6). Tira un error si no es
/// la última: un cierre viejo, una vez que se abrió un día nuevo, queda
/// cerrado para siempre.
Future<void> reabrirSesion(AppDatabase db, {required int sesionId}) async {
  if (!await esUltimaSesion(db, sesionId)) {
    throw StateError('Solo se puede reabrir la última sesión cerrada');
  }
  await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).write(
    SesionesDeCajaCompanion(estado: const Value('ABIERTA'), actualizadoEn: Value(DateTime.now())),
  );
}
