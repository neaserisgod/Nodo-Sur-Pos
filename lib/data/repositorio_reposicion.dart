// Reposición por proveedor (fase 6, Regla 5) y separación de fondos: cuánto
// hay que separar de cada proveedor, congelarlo al decidir hacerlo, y
// pagarlo sin perder un pago parcial en el camino.
//
// El corte de cada ciclo es `Proveedores.corteReposicionFecha`, que se
// mueve al separar (Regla 5 extendida) — nunca `historial_pedidos
// .fechaRecibido`: esa tabla queda sin usar (ver DECISIONES.md), el corte
// ahora es plata, no mercadería.
//
// Fase 13: este archivo resuelve el nivel 2 de la pantalla Proveedores (lo
// que se ve al entrar a uno — costo real pendiente, colchón, separar,
// pagar) y el nivel 3 "Avanzado" (código, días, activo). El nivel 1 (la
// lista resumida: stock valorizado, vendido, ganancia por período) vive en
// `repositorio_proveedores.dart` — un archivo distinto a propósito, porque
// esas cifras NO excluyen cigarrillos (son una foto general del negocio),
// mientras que todo lo de acá sí (Regla 6).

import 'package:drift/drift.dart';

import '../domain/ajuste_a_disponible.dart';
import '../domain/markup.dart';
import '../domain/reposicion.dart';
import '../domain/separacion_por_medio.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'linea_venta_reconstruccion.dart';
import 'repositorio_cierre.dart';

/// Dropdown en el editor de proveedor — texto libre no, mismo criterio que
/// `motivosAjusteDeStock` (`repositorio_productos.dart`).
const List<String> mediosPagoProveedor = [
  'Efectivo',
  'Transferencia',
  'Cuenta corriente',
  'Mercado Pago',
];

class ResumenReposicionProveedor {
  final Proveedor proveedor;

  /// Precio de venta desde el corte — lo que entró, no lo que costó
  /// (Bruno, ítem 3: la columna "VENDIDO" del papel es precio, confundirla
  /// con el costo real es un error de la planilla, no un dato que falte).
  final int vendidoCentavos;

  /// Costo real puro vendido desde el corte (sin colchón, sin arrastre).
  final int costoRealCentavos;

  /// Ganancia real vendida desde el corte (venta − costo, mismo corte que
  /// [costoRealCentavos]) — Regla 13: es uno de los datos que Bruno revisa
  /// por proveedor al abrir caja, para decidir cuánto retirar.
  final int gananciaCentavos;

  /// Ganancia retenida acumulada de este proveedor (Regla 13): ya no es un
  /// monto configurable a mano — crece solo cuando Bruno decide no
  /// llevarse la ganancia de este proveedor (`retenerGanancia`), y se
  /// consume al separar (ver `separarProveedor`).
  final int colchonCentavos;

  /// = `proveedor.pendienteBaseCentavos` + [costoRealCentavos]. Lo que
  /// todavía no se separó — sigue creciendo con cada venta nueva hasta la
  /// próxima separación.
  final int pendienteSinSepararCentavos;

  /// [pendienteSinSepararCentavos] + colchón — cuánto se congela al separar
  /// (Regla 13: el colchón, ahora ganancia real retenida, se suma al costo
  /// real y se consume en ese momento — ver `separarProveedor`).
  final int sugeridoASepararCentavos;

  /// Congelado desde la última separación, esperando pago. 0 si no hay
  /// nada separado.
  final int separadoCentavos;
  final DateTime? separadoFecha;

  /// Parte de [costoRealCentavos] que está en Mercado Pago, no en el cajón
  /// (Bruno, 2026-09-26, `lib/domain/separacion_por_medio.dart`): lo cobrado
  /// directo por MP más lo que los cigarrillos cobrados por MP le sacaron al
  /// efectivo. Es también la parte MP de [sugeridoASepararCentavos] — el
  /// colchón y el pendiente arrastrado van enteros del cajón (no hay forma
  /// de saber en qué medio quedó esa plata).
  final int costoRealMpCentavos;

  /// Parte de [separadoCentavos] congelada como "de Mercado Pago".
  final int separadoMpCentavos;

  int get sugeridoASepararEfectivoCentavos => sugeridoASepararCentavos - costoRealMpCentavos;
  int get separadoEfectivoCentavos => separadoCentavos - separadoMpCentavos;

  const ResumenReposicionProveedor({
    required this.proveedor,
    required this.vendidoCentavos,
    required this.costoRealCentavos,
    required this.gananciaCentavos,
    required this.colchonCentavos,
    required this.pendienteSinSepararCentavos,
    required this.sugeridoASepararCentavos,
    required this.separadoCentavos,
    required this.separadoFecha,
    required this.costoRealMpCentavos,
    required this.separadoMpCentavos,
  });
}

/// Todas las líneas (con la fecha de su venta) de los proveedores pedidos,
/// en una sola consulta — agrupadas por `proveedorIdFoto` para que cada
/// llamador filtre por SU PROPIO corte en memoria, sin volver a la base.
/// Reemplaza lo que antes era una consulta por proveedor (hasta ~15
/// round-trips secuenciales en `reposicionActual`/`gananciaPendienteDeProveedores`,
/// el doble cuando `proveedoresParaSeparar`/`reporteProveedores` llaman a
/// las dos): sin filtro de fecha acá porque cada proveedor tiene su propio
/// corte (`corteReposicionFecha` o `gananciaRevisadaFecha`, según quién
/// llame) — el corte se aplica después, por proveedor, en
/// [_resumenVentasDesdeCache].
Future<Map<int, List<(FilaLineaVenta linea, FilaVenta venta)>>>
_lineasPorProveedorDesde(AppDatabase db, List<int> proveedorIds) async {
  if (proveedorIds.isEmpty) return {};
  final query = db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  // Sin ventas anuladas (Bruno, 2026-09-26): una venta revertida no generó
  // nada que reponer, ni vendido, ni ganancia.
  ])..where(db.lineasDeVenta.proveedorIdFoto.isIn(proveedorIds) & db.ventas.anuladaEn.isNull());
  final filas = await query.get();

  final resultado = <int, List<(FilaLineaVenta, FilaVenta)>>{};
  for (final fila in filas) {
    final linea = fila.readTable(db.lineasDeVenta);
    resultado.putIfAbsent(linea.proveedorIdFoto!, () => []).add((linea, fila.readTable(db.ventas)));
  }
  return resultado;
}

/// Costo real y precio de venta del proveedor desde [corte] (o desde
/// siempre si es null), reconstruyendo las líneas igual que
/// `repositorio_cierre.dart` hace para el día — [filas] ya viene filtrado
/// por proveedor (una sola consulta compartida, [_lineasPorProveedorDesde]),
/// acá solo se aplica el corte de fecha, que sí es propio de cada llamador.
({int costoReal, int vendido, int ganancia}) _resumenVentasDesdeCache(
  List<(FilaLineaVenta, FilaVenta)> filas,
  Proveedor proveedor,
  DateTime? corte,
) {
  final lineas = _filasDesde(filas, corte)
      .map((par) => lineaParaReposicionDesde(par.$1, venta: par.$2))
      .toList();
  final resultado = calcularReposicion(lineas: lineas);
  final clave = proveedor.id.toString();
  return (
    costoReal: resultado.costoRealPorProveedorCentavos[clave] ?? 0,
    vendido: resultado.vendidoPorProveedorCentavos[clave] ?? 0,
    ganancia: resultado.gananciaPorProveedorCentavos[clave] ?? 0,
  );
}

Iterable<(FilaLineaVenta, FilaVenta)> _filasDesde(
  List<(FilaLineaVenta, FilaVenta)> filas,
  DateTime? corte,
) => filas.where((par) => corte == null || par.$2.fecha.isAfter(corte));

/// Parte "de Mercado Pago" del costo de cada línea
/// (`parteMpPorLinea`, `lib/domain/separacion_por_medio.dart`) para todas
/// las ventas desde [desde] (null = desde siempre). El reparto de los
/// cigarrillos cobrados por MP es por día, así que se cargan las sesiones
/// ENTERAS que tengan alguna venta después de [desde] — una sesión cortada
/// a la mitad repartiría el excedente de ese día sobre menos líneas de las
/// que de verdad quedaron en efectivo.
Future<Map<int, ParteMpDeLinea>> _parteMpDeLineasDesde(AppDatabase db, DateTime? desde) async {
  final sesionesQuery = db.selectOnly(db.ventas, distinct: true)
    ..addColumns([db.ventas.sesionCajaId]);
  if (desde != null) sesionesQuery.where(db.ventas.fecha.isBiggerThanValue(desde));
  final sesionIds = (await sesionesQuery.get())
      .map((f) => f.read(db.ventas.sesionCajaId)!)
      .toList();
  if (sesionIds.isEmpty) return {};

  final ventasFilas = await (db.select(db.ventas)
        ..where((v) => v.sesionCajaId.isIn(sesionIds) & v.anuladaEn.isNull()))
      .get();
  final ventaIds = ventasFilas.map((v) => v.id).toList();

  final lineasPorVenta = <int, List<FilaLineaVenta>>{};
  for (final l in await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.isIn(ventaIds))).get()) {
    lineasPorVenta.putIfAbsent(l.ventaId, () => []).add(l);
  }
  final mp = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
  final efectivoPorVenta = <int, int>{};
  final mpPorVenta = <int, int>{};
  for (final p in await (db.select(db.pagos)..where((p) => p.ventaId.isIn(ventaIds))).get()) {
    final destino = p.medioPagoId == mp.id ? mpPorVenta : efectivoPorVenta;
    destino.update(p.ventaId, (a) => a + p.montoCentavos, ifAbsent: () => p.montoCentavos);
  }

  return parteMpPorLinea([
    for (final v in ventasFilas)
      VentaParaSeparacion(
        sesionId: v.sesionCajaId,
        efectivoCentavos: efectivoPorVenta[v.id] ?? 0,
        mpCentavos: mpPorVenta[v.id] ?? 0,
        lineas: [
          for (final l in lineasPorVenta[v.id] ?? const <FilaLineaVenta>[]) _lineaParaSeparacion(l, v),
        ],
      ),
  ]);
}

LineaParaSeparacion _lineaParaSeparacion(FilaLineaVenta l, FilaVenta v) {
  // Los cigarrillos van a la lata a precio de lista (Regla 6): el descuento
  // de la venta solo achica la ganancia de las demás líneas.
  final r = lineaParaReposicionDesde(l, venta: v);
  final esCigarrillo = r.esCigarrillo;
  return LineaParaSeparacion(
    lineaId: l.id,
    esCigarrillo: esCigarrillo,
    costoLineaCentavos: r.costoLineaCentavos,
    precioLineaCentavos: esCigarrillo ? lineaParaReposicionDesde(l).precioLineaCentavos : r.precioLineaCentavos,
    tieneProveedor: r.proveedorId != null,
  );
}

/// El corte más viejo entre [proveedores] — desde ahí hace falta conocer la
/// parte MP de las líneas. Null si alguno nunca cortó (desde siempre).
DateTime? _corteMasViejo(Iterable<Proveedor> proveedores) {
  DateTime? masViejo;
  for (final p in proveedores) {
    final corte = p.corteReposicionFecha;
    if (corte == null) return null;
    if (masViejo == null || corte.isBefore(masViejo)) masViejo = corte;
  }
  return masViejo;
}

// ─── Separaciones del día (Bruno, 2026-09-26: "la idea es que sea del día!!
// y tenga en cuenta los montos actuales tanto de efectivo como de mp") ─────

DateTime _inicioDelDia(DateTime ahora) => DateTime(ahora.year, ahora.month, ahora.day);

/// Una fila de la pantalla "Separaciones": lo de HOY de un proveedor (todos
/// los turnos del día), dividido entre cajón y Mercado Pago. Lo que haya
/// quedado sin separar de días anteriores no aparece acá (decisión de
/// Bruno) — sigue vivo en Proveedores → Avanzado.
class SeparacionDelDia {
  /// Null en la fila "Sin proveedor": se muestra (Bruno, 2026-09-26: "lo
  /// mismo sin proveedor"), pero no hay a quién separarle ni pagarle.
  final Proveedor? proveedor;

  /// Todo lo vendido hoy, con y sin costo cargado.
  final int vendidoCentavos;

  /// La parte de [vendidoCentavos] sin costo cargado ("Varios", o un
  /// producto al que todavía no se le cargó el costo) — no entra en la
  /// reposición ni en la ganancia, porque no se sabe cuánto costó.
  final int vendidoSinCostoCentavos;

  /// Reposición (costo) y ganancia de las líneas CON costo: vendido con
  /// costo = costo + ganancia (costo + markup).
  final int costoCentavos;
  final int gananciaCentavos;
  final int gananciaMpCentavos;

  /// Reposición de hoy todavía sin separar (lo que se vendió hoy después del
  /// último "Separar"), y su parte en MP — antes de ajustar a lo que hay en
  /// cada caja (eso lo hace [ajustarSeparacionesADisponible]). Siempre 0 en
  /// "Sin proveedor".
  final int faltaSepararCentavos;
  final int faltaSepararMpCentavos;

  final int separadoCentavos;
  final int separadoMpCentavos;
  final DateTime? separadoFecha;

  /// Lo que se tildó como separado HOY desde "Separaciones" (0 si no), y si
  /// se puede destildar ([puedeDesmarcarDelDia]).
  final int separadoHoyCentavos;
  final int separadoHoyMpCentavos;
  final bool puedeDesmarcar;

  const SeparacionDelDia({
    required this.proveedor,
    required this.vendidoCentavos,
    required this.vendidoSinCostoCentavos,
    required this.costoCentavos,
    required this.gananciaCentavos,
    required this.gananciaMpCentavos,
    required this.faltaSepararCentavos,
    required this.faltaSepararMpCentavos,
    required this.separadoCentavos,
    required this.separadoMpCentavos,
    required this.separadoFecha,
    this.separadoHoyCentavos = 0,
    this.separadoHoyMpCentavos = 0,
    this.puedeDesmarcar = false,
  });

  /// Tildada: se separó hoy y no se vendió nada nuevo después.
  bool get separadaHoy => separadoHoyCentavos > 0 && faltaSepararCentavos == 0;

  String get nombre => proveedor?.nombre ?? 'Sin proveedor';
  int get gananciaEfectivoCentavos => gananciaCentavos - gananciaMpCentavos;
  int get separadoEfectivoCentavos => separadoCentavos - separadoMpCentavos;
}

/// Suma de las líneas del período de un proveedor (o de las sin
/// proveedor). Lo que falta separar cuenta solo lo vendido desde
/// [inicioHoy] y después del último [corte] — Separaciones es del día.
({int vendido, int sinCosto, int costo, int gananciaMp, int falta, int faltaMp}) _sumarDelDia(
  Iterable<(FilaLineaVenta, FilaVenta)> lineas,
  DateTime? corte,
  DateTime inicioHoy,
  Map<int, ParteMpDeLinea> parteMp,
) {
  var vendido = 0, sinCosto = 0, costo = 0, gananciaMp = 0, falta = 0, faltaMp = 0;
  for (final (linea, venta) in lineas) {
    final fecha = venta.fecha;
    final r = lineaParaReposicionDesde(linea, venta: venta);
    if (r.esCigarrillo) continue;
    vendido += r.precioLineaCentavos;
    if (r.costoLineaCentavos == null) {
      sinCosto += r.precioLineaCentavos;
      continue;
    }
    costo += r.costoLineaCentavos!;
    gananciaMp += parteMp[linea.id]?.gananciaMpCentavos ?? 0;
    if (!fecha.isBefore(inicioHoy) && (corte == null || fecha.isAfter(corte))) {
      falta += r.costoLineaCentavos!;
      faltaMp += parteMp[linea.id]?.costoMpCentavos ?? 0;
    }
  }
  return (vendido: vendido, sinCosto: sinCosto, costo: costo, gananciaMp: gananciaMp, falta: falta, faltaMp: faltaMp);
}

/// Todos los proveedores activos (salvo Serra Cigarros: su reposición la
/// hace la lata) con algo vendido hoy o algo separado esperando pago, más
/// una fila "Sin proveedor" al final si hoy se vendió algo sin proveedor.
Future<List<SeparacionDelDia>> separacionesDelDia(AppDatabase db, {DateTime? ahora, DateTime? desde}) async {
  final momento = ahora ?? DateTime.now();
  // [desde] (vista "Lo vendido", semana/mes) cambia desde cuándo se suma lo
  // vendido; lo que falta separar sigue siendo solo lo de hoy.
  final inicioHoy = _inicioDelDia(momento);
  final inicio = desde ?? inicioHoy;
  final antesDelInicio = inicio.subtract(const Duration(microseconds: 1));
  final proveedores = await (db.select(
    db.proveedores,
  )..where((p) => p.activo.equals(true) & p.cajaAparte.equals(false))).get();
  final filasPorProveedor = await _lineasPorProveedorDesde(db, proveedores.map((p) => p.id).toList());
  final parteMp = await _parteMpDeLineasDesde(db, inicio);

  final resultado = <SeparacionDelDia>[];
  for (final proveedor in proveedores) {
    final periodo = _filasDesde(filasPorProveedor[proveedor.id] ?? const [], antesDelInicio);
    final t = _sumarDelDia(periodo, proveedor.corteReposicionFecha, inicioHoy, parteMp);
    if (t.vendido == 0 && proveedor.separadoCentavos == 0) continue;
    resultado.add(
      SeparacionDelDia(
        proveedor: proveedor,
        vendidoCentavos: t.vendido,
        vendidoSinCostoCentavos: t.sinCosto,
        costoCentavos: t.costo,
        gananciaCentavos: t.vendido - t.sinCosto - t.costo,
        gananciaMpCentavos: t.gananciaMp,
        faltaSepararCentavos: t.falta,
        faltaSepararMpCentavos: t.faltaMp,
        separadoCentavos: proveedor.separadoCentavos,
        separadoMpCentavos: proveedor.separadoMpCentavos,
        separadoFecha: proveedor.separadoFecha,
        separadoHoyCentavos: _esDelDia(proveedor.separadoDelDiaFecha, momento) ? proveedor.separadoDelDiaCentavos : 0,
        separadoHoyMpCentavos: _esDelDia(proveedor.separadoDelDiaFecha, momento) ? proveedor.separadoDelDiaMpCentavos : 0,
        puedeDesmarcar: puedeDesmarcarDelDia(proveedor, ahora: momento),
      ),
    );
  }
  resultado.sort((a, b) => a.nombre.compareTo(b.nombre));

  final sinProveedor = _sumarDelDia(await _lineasSinProveedorDesde(db, antesDelInicio), null, inicioHoy, parteMp);
  if (sinProveedor.vendido != 0) {
    resultado.add(
      SeparacionDelDia(
        proveedor: null,
        vendidoCentavos: sinProveedor.vendido,
        vendidoSinCostoCentavos: sinProveedor.sinCosto,
        costoCentavos: sinProveedor.costo,
        gananciaCentavos: sinProveedor.vendido - sinProveedor.sinCosto - sinProveedor.costo,
        gananciaMpCentavos: sinProveedor.gananciaMp,
        faltaSepararCentavos: 0,
        faltaSepararMpCentavos: 0,
        separadoCentavos: 0,
        separadoMpCentavos: 0,
        separadoFecha: null,
      ),
    );
  }
  return resultado;
}

/// Un producto vendido sin costo cargado, sumado en el período — lo que
/// muestra el aviso "…sin costo cargado" al tocarlo (Bruno, 2026-09-26:
/// "que si hago click me diga el producto sin costo").
class VendidoSinCosto {
  /// Para cargarle el costo desde el mismo aviso (mock `DialogosSeparaciones`
  /// → Productos sin costo). Null en líneas sin producto de catálogo.
  final int? productoId;
  final bool esPesable;
  final String producto;

  /// Null si la venta no tenía proveedor.
  final String? proveedor;

  /// Unidades vendidas; en pesables, [gramos] en su lugar.
  final int cantidad;
  final int gramos;
  final int vendidoCentavos;

  const VendidoSinCosto({
    required this.productoId,
    required this.esPesable,
    required this.producto,
    required this.proveedor,
    required this.cantidad,
    required this.gramos,
    required this.vendidoCentavos,
  });
}

/// Los productos vendidos sin costo cargado desde [desde] (ventas no
/// anuladas, sin cigarrillos — mismo criterio que lo que suma a "vendido sin
/// costo" en Separaciones), agrupados por producto y proveedor, de mayor a
/// menor vendido.
Future<List<VendidoSinCosto>> vendidoSinCostoDesde(AppDatabase db, DateTime desde) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
    leftOuterJoin(db.proveedores, db.proveedores.id.equalsExp(db.lineasDeVenta.proveedorIdFoto)),
  ])
        ..where(
          db.lineasDeVenta.costoUnitarioCentavos.isNull() &
              db.lineasDeVenta.tipoCigarrillo.equals('ninguno') &
              db.ventas.anuladaEn.isNull() &
              db.ventas.fecha.isBiggerOrEqualValue(desde),
        ))
      .get();

  final grupos = <(int?, bool, String, String?), ({int cantidad, int gramos, int vendido})>{};
  for (final f in filas) {
    final linea = f.readTable(db.lineasDeVenta);
    final ventaFila = f.readTable(db.ventas);
    final clave = (linea.productoId, linea.esPesable, linea.nombreProductoFoto, f.readTableOrNull(db.proveedores)?.nombre);
    final previo = grupos[clave] ?? (cantidad: 0, gramos: 0, vendido: 0);
    grupos[clave] = (
      cantidad: previo.cantidad + (linea.esPesable ? 0 : (linea.cantidad ?? 1)),
      gramos: previo.gramos + (linea.esPesable ? (linea.gramos ?? 0) : 0),
      vendido: previo.vendido + lineaParaReposicionDesde(linea, venta: ventaFila).precioLineaCentavos,
    );
  }
  return [
    for (final MapEntry(key: (productoId, esPesable, producto, proveedor), value: v) in grupos.entries)
      VendidoSinCosto(
        productoId: productoId,
        esPesable: esPesable,
        producto: producto,
        proveedor: proveedor,
        cantidad: v.cantidad,
        gramos: v.gramos,
        vendidoCentavos: v.vendido,
      ),
  ]..sort((a, b) => b.vendidoCentavos.compareTo(a.vendidoCentavos));
}

/// Las líneas sin proveedor de ventas no anuladas desde [desde].
Future<List<(FilaLineaVenta, FilaVenta)>> _lineasSinProveedorDesde(AppDatabase db, DateTime desde) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(
          db.lineasDeVenta.proveedorIdFoto.isNull() &
              db.ventas.anuladaEn.isNull() &
              db.ventas.fecha.isBiggerThanValue(desde),
        ))
      .get();
  return [for (final f in filas) (f.readTable(db.lineasDeVenta), f.readTable(db.ventas))];
}

/// La plata que hay AHORA para separar, de la caja abierta: el efectivo que
/// debería haber en el cajón menos lo que se va a llevar la lata al cerrar
/// (cigarrillos de hoy + pendiente de cierres anteriores, Regla 6) y menos
/// lo ya separado en efectivo esperando pago (sigue físicamente en el cajón,
/// pero ya tiene dueño); y el saldo de Mercado Pago menos lo ya separado
/// ahí. No descuenta el fondo para dar vuelto — es la plata que hay, no la
/// que conviene dejar.
class DisponibleParaSeparar {
  final int efectivoEnCajonCentavos;
  final int seLlevaLaLataCentavos;
  final int separadoEfectivoCentavos;
  final int saldoMpCentavos;
  final int separadoMpCentavos;

  const DisponibleParaSeparar({
    required this.efectivoEnCajonCentavos,
    required this.seLlevaLaLataCentavos,
    required this.separadoEfectivoCentavos,
    required this.saldoMpCentavos,
    required this.separadoMpCentavos,
  });

  int get efectivoDisponibleCentavos =>
      efectivoEnCajonCentavos - seLlevaLaLataCentavos - separadoEfectivoCentavos;
  int get mpDisponibleCentavos => saldoMpCentavos - separadoMpCentavos;
}

Future<DisponibleParaSeparar> disponibleParaSepararAhora(AppDatabase db, int sesionId) async {
  final enVivo = await estadoCajaEnVivo(db, sesionId);
  final cigarrillosHoy = await precioListaCigarrillosDelDia(db, sesionId);
  final anterior = await sesionCerradaAnterior(db, sesionId);
  final proveedores = await db.select(db.proveedores).get();
  final separado = proveedores.fold<int>(0, (a, p) => a + p.separadoCentavos);
  final separadoMp = proveedores.fold<int>(0, (a, p) => a + p.separadoMpCentavos);
  return DisponibleParaSeparar(
    efectivoEnCajonCentavos: enVivo.efectivoEsperadoCentavos,
    seLlevaLaLataCentavos: cigarrillosHoy + (anterior?.lataPendienteCentavos ?? 0),
    separadoEfectivoCentavos: separado - separadoMp,
    saldoMpCentavos: enVivo.mpEsperadoCentavos,
    separadoMpCentavos: separadoMp,
  );
}

/// Ajusta la división cajón/MP de lo que falta separar hoy a [disponible]
/// (`lib/domain/ajuste_a_disponible.dart`). Sin [disponible] (no hay caja
/// abierta) queda la división según cómo se cobró, sin ajustar.
ResultadoAjuste<int> ajustarSeparacionesADisponible(
  List<SeparacionDelDia> filas,
  DisponibleParaSeparar? disponible,
) {
  final partes = {
    for (final f in filas)
      if (f.proveedor != null && f.faltaSepararCentavos > 0)
        f.proveedor!.id: ParteSeparacion(
          efectivoCentavos: f.faltaSepararCentavos - f.faltaSepararMpCentavos,
          mpCentavos: f.faltaSepararMpCentavos,
        ),
  };
  if (disponible == null) {
    return ResultadoAjuste(partes: partes, corridoAMpCentavos: 0, faltanteCentavos: 0);
  }
  return ajustarADisponible(
    partes: partes,
    efectivoDisponibleCentavos: disponible.efectivoDisponibleCentavos,
    mpDisponibleCentavos: disponible.mpDisponibleCentavos,
  );
}

/// Separa lo de HOY de un proveedor (desde "Separaciones"): congela la
/// reposición vendida hoy desde su último corte, con [montoMpCentavos] como
/// parte de Mercado Pago (la ya ajustada a lo que hay en cada caja). A
/// diferencia de [separarProveedor]:
/// - lo que quedó sin separar de días anteriores NO se separa (decisión de
///   Bruno: Separaciones es solo del día) — pasa a `pendienteBaseCentavos`
///   para que siga apareciendo en Proveedores → Avanzado;
/// - el colchón no se toca.
Future<void> separarDelDia(
  AppDatabase db, {
  required int proveedorId,
  required int montoMpCentavos,
  DateTime? ahora,
}) async {
  final momento = ahora ?? DateTime.now();
  final inicio = _inicioDelDia(momento);
  final proveedor = await (db.select(db.proveedores)..where((p) => p.id.equals(proveedorId))).getSingle();
  final filas = (await _lineasPorProveedorDesde(db, [proveedorId]))[proveedorId] ?? const [];
  final corte = proveedor.corteReposicionFecha;

  var deHoy = 0, deAntes = 0;
  for (final (linea, venta) in _filasDesde(filas, corte)) {
    final fecha = venta.fecha;
    final r = lineaParaReposicionDesde(linea, venta: venta);
    if (r.esCigarrillo || r.costoLineaCentavos == null) continue;
    if (fecha.isBefore(inicio)) {
      deAntes += r.costoLineaCentavos!;
    } else {
      deHoy += r.costoLineaCentavos!;
    }
  }
  if (deHoy <= 0) return;
  final mp = montoMpCentavos.clamp(0, deHoy);

  // Una segunda separación el mismo día (se vendió más después de tildar)
  // suma a la del día; "cómo estaba antes" queda el de la primera, así
  // destildar vuelve al estado de la mañana.
  final yaSeparoHoy = _esDelDia(proveedor.separadoDelDiaFecha, momento);
  await (db.update(db.proveedores)..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      separadoCentavos: Value(proveedor.separadoCentavos + deHoy),
      separadoMpCentavos: Value(proveedor.separadoMpCentavos + mp),
      separadoFecha: Value(momento),
      corteReposicionFecha: Value(momento),
      pendienteBaseCentavos: Value(proveedor.pendienteBaseCentavos + deAntes),
      separadoDelDiaFecha: Value(momento),
      separadoDelDiaCentavos: Value((yaSeparoHoy ? proveedor.separadoDelDiaCentavos : 0) + deHoy),
      separadoDelDiaMpCentavos: Value((yaSeparoHoy ? proveedor.separadoDelDiaMpCentavos : 0) + mp),
      corteAntesDelDia: Value(yaSeparoHoy ? proveedor.corteAntesDelDia : proveedor.corteReposicionFecha),
      pendienteBaseAntesDelDiaCentavos: Value(
        yaSeparoHoy ? proveedor.pendienteBaseAntesDelDiaCentavos : proveedor.pendienteBaseCentavos,
      ),
      actualizadoEn: Value(DateTime.now()),
    ),
  );
}

bool _esDelDia(DateTime? fecha, DateTime ahora) =>
    fecha != null && fecha.year == ahora.year && fecha.month == ahora.month && fecha.day == ahora.day;

/// true si lo separado hoy de [proveedor] todavía se puede destildar: se
/// separó hoy y no se pagó después (un pago pone lo separado en 0 — deshacer
/// ahí restaría plata que ya se entregó).
bool puedeDesmarcarDelDia(Proveedor proveedor, {DateTime? ahora}) =>
    _esDelDia(proveedor.separadoDelDiaFecha, ahora ?? DateTime.now()) &&
    proveedor.separadoDelDiaCentavos > 0 &&
    proveedor.separadoCentavos >= proveedor.separadoDelDiaCentavos;

/// Destilda la tarjeta de un proveedor en "Separaciones": deshace lo
/// separado hoy y lo deja exactamente como estaba antes de la primera
/// separación del día (corte y pendiente arrastrado incluidos). No hace nada
/// si no se puede ([puedeDesmarcarDelDia]).
Future<void> desmarcarDelDia(AppDatabase db, {required int proveedorId, DateTime? ahora}) async {
  final proveedor = await (db.select(db.proveedores)..where((p) => p.id.equals(proveedorId))).getSingle();
  if (!puedeDesmarcarDelDia(proveedor, ahora: ahora)) return;
  final separado = proveedor.separadoCentavos - proveedor.separadoDelDiaCentavos;
  await (db.update(db.proveedores)..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      separadoCentavos: Value(separado),
      separadoMpCentavos: Value(proveedor.separadoMpCentavos - proveedor.separadoDelDiaMpCentavos),
      // Sin nada separado, no hay fecha que mostrar; si quedaba algo de
      // antes de hoy, su fecha real se perdió al separar — queda la de hoy
      // (dato informativo nada más).
      separadoFecha: Value(separado == 0 ? null : proveedor.separadoFecha),
      corteReposicionFecha: Value(proveedor.corteAntesDelDia),
      pendienteBaseCentavos: Value(proveedor.pendienteBaseAntesDelDiaCentavos),
      separadoDelDiaFecha: const Value(null),
      separadoDelDiaCentavos: const Value(0),
      separadoDelDiaMpCentavos: const Value(0),
      corteAntesDelDia: const Value(null),
      pendienteBaseAntesDelDiaCentavos: const Value(0),
      actualizadoEn: Value(DateTime.now()),
    ),
  );
}

/// Lo cobrado HOY (todas las ventas no anuladas del día, todos los turnos)
/// por caja, y el precio de lista de los cigarrillos vendidos hoy — lo que
/// la lata se lleva en efectivo al cierre (Regla 6), sin importar cómo se
/// cobraron.
Future<({int efectivoCentavos, int mpCentavos, int cigarrillosCentavos})> cobradoDelDia(
  AppDatabase db, {
  DateTime? ahora,
}) async {
  final inicio = _inicioDelDia(ahora ?? DateTime.now());
  final ventas = await (db.select(db.ventas)
        ..where((v) => v.fecha.isBiggerOrEqualValue(inicio) & v.anuladaEn.isNull()))
      .get();
  final ids = ventas.map((v) => v.id).toList();
  if (ids.isEmpty) return (efectivoCentavos: 0, mpCentavos: 0, cigarrillosCentavos: 0);
  final mp = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
  var efectivo = 0, virtual = 0;
  for (final p in await (db.select(db.pagos)..where((p) => p.ventaId.isIn(ids))).get()) {
    if (p.medioPagoId == mp.id) {
      virtual += p.montoCentavos;
    } else {
      efectivo += p.montoCentavos;
    }
  }
  var cigarrillos = 0;
  for (final l in await (db.select(db.lineasDeVenta)
        ..where((l) => l.ventaId.isIn(ids) & l.tipoCigarrillo.isNotValue('ninguno')))
      .get()) {
    cigarrillos += lineaParaReposicionDesde(l).precioLineaCentavos;
  }
  return (efectivoCentavos: efectivo, mpCentavos: virtual, cigarrillosCentavos: cigarrillos);
}

/// Público (fase 13, pantalla Proveedores, nivel 2): a diferencia de
/// [reposicionActual], no excluye a Serra Cigarros — acá se pide un
/// proveedor puntual porque Bruno ya entró a verlo, así que sus cifras en
/// cero (correctas: los cigarrillos quedan fuera de `calcularReposicion`,
/// Regla 6) son información real de ESE proveedor, no ruido en una lista de
/// quince filas.
Future<ResumenReposicionProveedor> resumenReposicionDeProveedor(
  AppDatabase db,
  Proveedor proveedor,
) async {
  final filas = await _lineasPorProveedorDesde(db, [proveedor.id]);
  final parteMp = await _parteMpDeLineasDesde(db, proveedor.corteReposicionFecha);
  return _resumenDe(proveedor, filas[proveedor.id] ?? const [], parteMp);
}

ResumenReposicionProveedor _resumenDe(
  Proveedor proveedor,
  List<(FilaLineaVenta, FilaVenta)> filas,
  Map<int, ParteMpDeLinea> parteMpPorLinea,
) {
  final ventas = _resumenVentasDesdeCache(
    filas,
    proveedor,
    proveedor.corteReposicionFecha,
  );
  final costoRealMp = _filasDesde(filas, proveedor.corteReposicionFecha)
      .fold<int>(0, (a, par) => a + (parteMpPorLinea[par.$1.id]?.costoMpCentavos ?? 0));
  final pendienteSinSeparar =
      proveedor.pendienteBaseCentavos + ventas.costoReal;

  return ResumenReposicionProveedor(
    proveedor: proveedor,
    vendidoCentavos: ventas.vendido,
    costoRealCentavos: ventas.costoReal,
    gananciaCentavos: ventas.ganancia,
    colchonCentavos: proveedor.colchonReposicionCentavos,
    pendienteSinSepararCentavos: pendienteSinSeparar,
    sugeridoASepararCentavos:
        pendienteSinSeparar + proveedor.colchonReposicionCentavos,
    separadoCentavos: proveedor.separadoCentavos,
    separadoFecha: proveedor.separadoFecha,
    costoRealMpCentavos: costoRealMp,
    separadoMpCentavos: proveedor.separadoMpCentavos,
  );
}

/// Reposición actual de cada proveedor activo — salvo Serra Cigarros (código
/// SC): sus ventas quedan afuera de `calcularReposicion` a propósito (Regla
/// 6, `esCigarrillo`), así que siempre daría separado/pendiente en cero. Una
/// fila permanentemente en cero es ruido, no información — se paga desde la
/// lata (`pagosALataDelDia`), no desde acá.
Future<List<ResumenReposicionProveedor>> reposicionActual(
  AppDatabase db,
) async {
  final proveedores = await (db.select(
    db.proveedores,
  )..where((p) => p.activo.equals(true) & p.cajaAparte.equals(false))).get();
  final filasPorProveedor = await _lineasPorProveedorDesde(
    db,
    proveedores.map((p) => p.id).toList(),
  );
  final parteMp = await _parteMpDeLineasDesde(db, _corteMasViejo(proveedores));
  return [
    for (final proveedor in proveedores)
      _resumenDe(proveedor, filasPorProveedor[proveedor.id] ?? const [], parteMp),
  ];
}

class GananciaPendienteProveedor {
  final Proveedor proveedor;
  final int vendidoCentavos;
  final int gananciaCentavos;

  const GananciaPendienteProveedor({
    required this.proveedor,
    required this.vendidoCentavos,
    required this.gananciaCentavos,
  });
}

/// Un proveedor con algo para hacer en la pantalla simplificada de "separar"
/// (Bruno, 2026-09-05: "necesito que solo diga cuánto separar... para
/// ahorrarme trabajo y sobre todo tiempo"). Junta los dos cortes que ya
/// existían por separado (reposición — `corteReposicionFecha` — y ganancia —
/// `gananciaRevisadaFecha`) en una sola fila por proveedor, sin fusionar los
/// cortes en sí: cada número sigue viniendo de su función ya probada
/// ([reposicionActual] / [gananciaPendienteDeProveedores]).
class ProveedorParaSeparar {
  final Proveedor proveedor;

  /// = `ResumenReposicionProveedor.sugeridoASepararCentavos` (costo real
  /// pendiente + colchón). "Separar todo" actúa sobre este número.
  final int sugeridoASepararCentavos;

  /// Ganancia sin revisar desde `gananciaRevisadaFecha` — un corte
  /// DISTINTO al de arriba, puede tener plata pendiente aunque el otro esté
  /// en cero. "Separar ganancia" actúa sobre este número.
  final int gananciaSinRevisarCentavos;

  const ProveedorParaSeparar({
    required this.proveedor,
    required this.sugeridoASepararCentavos,
    required this.gananciaSinRevisarCentavos,
  });
}

/// Solo proveedores con algo pendiente en cualquiera de los dos cortes — uno
/// al día en los dos no tiene nada que Bruno tenga que decidir acá.
Future<List<ProveedorParaSeparar>> proveedoresParaSeparar(
  AppDatabase db,
) async {
  final reposicion = await reposicionActual(db);
  final gananciaPendiente = await gananciaPendienteDeProveedores(db);
  final gananciaPorProveedorId = {
    for (final g in gananciaPendiente) g.proveedor.id: g.gananciaCentavos,
  };

  final resultado = <ProveedorParaSeparar>[];
  for (final r in reposicion) {
    final ganancia = gananciaPorProveedorId[r.proveedor.id] ?? 0;
    if (r.sugeridoASepararCentavos <= 0 && ganancia <= 0) continue;
    resultado.add(
      ProveedorParaSeparar(
        proveedor: r.proveedor,
        sugeridoASepararCentavos: r.sugeridoASepararCentavos,
        gananciaSinRevisarCentavos: ganancia,
      ),
    );
  }
  return resultado;
}

/// Regla 13: ganancia por proveedor desde la última revisión
/// (`gananciaRevisadaFecha` — corte propio, independiente del de
/// reposición, ver el comentario de la columna). Es lo que Bruno mira al
/// abrir caja para decidir cuánto retirar y cuánto dejar como colchón.
/// Excluye a Serra Cigarros (SC), mismo motivo que [reposicionActual]: sus
/// ventas quedan afuera del cálculo de ganancia por proveedor (Regla 6, la
/// administra la lata aparte), así que siempre daría cero.
///
/// Solo devuelve proveedores con algo que revisar (vendido != 0 desde el
/// corte) — uno sin movimiento no tiene nada que Bruno tenga que decidir.
Future<List<GananciaPendienteProveedor>> gananciaPendienteDeProveedores(
  AppDatabase db,
) async {
  final proveedores = await (db.select(
    db.proveedores,
  )..where((p) => p.activo.equals(true) & p.cajaAparte.equals(false))).get();
  final filasPorProveedor = await _lineasPorProveedorDesde(
    db,
    proveedores.map((p) => p.id).toList(),
  );

  final resultados = <GananciaPendienteProveedor>[];
  for (final proveedor in proveedores) {
    final ventas = _resumenVentasDesdeCache(
      filasPorProveedor[proveedor.id] ?? const [],
      proveedor,
      proveedor.gananciaRevisadaFecha,
    );
    if (ventas.vendido == 0) continue;
    resultados.add(
      GananciaPendienteProveedor(
        proveedor: proveedor,
        vendidoCentavos: ventas.vendido,
        gananciaCentavos: ventas.ganancia,
      ),
    );
  }
  return resultados;
}

/// Una fila de "Reportes" (Bruno, 2026-09-06: "en lugar de revisar
/// ganancias, un apartado de reportes para poder ver detalladamente
/// todo") — junta en un solo lugar los dos cortes independientes de Regla
/// 13 (reposición y ganancia) para UN proveedor, sin fusionarlos: cada
/// cifra sigue viniendo de su función ya probada.
class ReporteProveedor {
  final Proveedor proveedor;

  final int vendidoCentavos;
  final int costoRealCentavos;
  final int pendienteSinSepararCentavos;
  final int sugeridoASepararCentavos;
  final int separadoCentavos;
  final DateTime? separadoFecha;
  final int colchonCentavos;

  /// Corte independiente (`gananciaRevisadaFecha`), no el mismo que
  /// [sugeridoASepararCentavos] — puede tener plata pendiente aunque el
  /// otro esté en cero.
  final int gananciaSinRevisarCentavos;

  const ReporteProveedor({
    required this.proveedor,
    required this.vendidoCentavos,
    required this.costoRealCentavos,
    required this.pendienteSinSepararCentavos,
    required this.sugeridoASepararCentavos,
    required this.separadoCentavos,
    required this.separadoFecha,
    required this.colchonCentavos,
    required this.gananciaSinRevisarCentavos,
  });
}

/// Reemplaza a la pantalla de apertura forzada: ya no interrumpe, es una
/// sección más de la barra lateral que se visita cuando se quiere — así
/// que, a diferencia de [proveedoresParaSeparar] (que solo lista lo
/// pendiente, pensado para no interrumpir con ruido en medio de la
/// apertura), acá se listan TODOS los proveedores activos (salvo Serra
/// Cigarros, Regla 6, mismo motivo que [reposicionActual]) — "ver
/// detalladamente todo" incluye los que están en cero.
Future<List<ReporteProveedor>> reporteProveedores(AppDatabase db) async {
  final reposicion = await reposicionActual(db);
  final gananciaPendiente = await gananciaPendienteDeProveedores(db);
  final gananciaPorProveedorId = {
    for (final g in gananciaPendiente) g.proveedor.id: g.gananciaCentavos,
  };

  return [
    for (final r in reposicion)
      ReporteProveedor(
        proveedor: r.proveedor,
        vendidoCentavos: r.vendidoCentavos,
        costoRealCentavos: r.costoRealCentavos,
        pendienteSinSepararCentavos: r.pendienteSinSepararCentavos,
        sugeridoASepararCentavos: r.sugeridoASepararCentavos,
        separadoCentavos: r.separadoCentavos,
        separadoFecha: r.separadoFecha,
        colchonCentavos: r.colchonCentavos,
        gananciaSinRevisarCentavos: gananciaPorProveedorId[r.proveedor.id] ?? 0,
      ),
  ];
}

/// De qué medio sale un retiro de ganancia real (Regla 13) — calculado
/// automáticamente según cómo se cobró cada venta que la generó (Bruno,
/// 2026-09-06: "de qué medio debe calcularse desde cómo se vendió"), no
/// tipeado a mano. Agrupa las líneas de [proveedor] desde
/// `gananciaRevisadaFecha` por venta (a diferencia de
/// [_resumenVentasDesde], que las suma todas juntas) porque el reparto
/// efectivo/virtual es por venta, no por proveedor:
/// [prorratearGananciaPorMedio] resuelve cada una y esto acumula.
///
/// Es un valor de partida, no una atribución exacta — la pantalla deja los
/// dos montos editables antes de confirmar, para el caso (mixto de varios
/// productos) sin atribución exacta por línea (limitación conocida, ver
/// ESTADO.md).
Future<({int efectivoCentavos, int virtualCentavos})> gananciaPorMedioDesde(
  AppDatabase db,
  Proveedor proveedor,
) async {
  final corte = proveedor.gananciaRevisadaFecha;
  final query =
      db.select(db.lineasDeVenta).join([
        innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
      ])..where(
        db.lineasDeVenta.proveedorIdFoto.equals(proveedor.id) &
            db.ventas.anuladaEn.isNull() &
            (corte == null
                ? const Constant(true)
                : db.ventas.fecha.isBiggerThanValue(corte)),
      );
  final filas = await query.get();

  final lineasPorVenta = <int, List<FilaLineaVenta>>{};
  final ventaPorId = <int, FilaVenta>{};
  for (final fila in filas) {
    final linea = fila.readTable(db.lineasDeVenta);
    ventaPorId[linea.ventaId] = fila.readTable(db.ventas);
    lineasPorVenta.update(
      linea.ventaId,
      (l) => l..add(linea),
      ifAbsent: () => [linea],
    );
  }

  final clave = proveedor.id.toString();

  // Las dos tablas chicas que el loop de abajo necesitaba consultar por
  // cada pago de cada venta (`mediosDePago`, 2 filas totales) y por cada
  // venta (`pagos`) se traen una sola vez cada una — antes eran hasta
  // varios cientos de round-trips evitables en un proveedor con muchas
  // ventas sin revisar.
  final esEfectivoPorMedioId = {
    for (final medio in await db.select(db.mediosDePago).get())
      medio.id: medio.esEfectivo,
  };
  final pagosPorVenta = <int, List<Pago>>{};
  if (lineasPorVenta.isNotEmpty) {
    final pagos = await (db.select(
      db.pagos,
    )..where((p) => p.ventaId.isIn(lineasPorVenta.keys))).get();
    for (final pago in pagos) {
      pagosPorVenta.putIfAbsent(pago.ventaId, () => []).add(pago);
    }
  }

  var efectivoTotal = 0;
  var virtualTotal = 0;
  for (final entry in lineasPorVenta.entries) {
    final lineas = entry.value.map((l) => lineaParaReposicionDesde(l, venta: ventaPorId[entry.key])).toList();
    final gananciaVenta =
        calcularReposicion(
          lineas: lineas,
        ).gananciaPorProveedorCentavos[clave] ??
        0;
    if (gananciaVenta == 0) continue;

    var efectivoVenta = 0;
    var virtualVenta = 0;
    for (final pago in pagosPorVenta[entry.key] ?? const <Pago>[]) {
      if (esEfectivoPorMedioId[pago.medioPagoId] ?? false) {
        efectivoVenta += pago.montoCentavos;
      } else {
        virtualVenta += pago.montoCentavos;
      }
    }
    // Sin pagos registrados para esta venta (no debería pasar en una venta
    // real, pero un día cargado a mano o un dato viejo podría no tenerlos):
    // no hay de dónde sacar la proporción, así que esta venta no aporta al
    // reparto en vez de dividir por cero — su ganancia sigue completa en
    // `gananciaSinRevisarCentavos` de la pantalla, solo no entra en la
    // sugerencia de "de qué medio".
    if (efectivoVenta + virtualVenta == 0) continue;

    final split = prorratearGananciaPorMedio(
      gananciaCentavos: gananciaVenta,
      efectivoDeLaVentaCentavos: efectivoVenta,
      virtualDeLaVentaCentavos: virtualVenta,
    );
    efectivoTotal += split.efectivoCentavos;
    virtualTotal += split.virtualCentavos;
  }

  return (efectivoCentavos: efectivoTotal, virtualCentavos: virtualTotal);
}

/// Regla 13: registra la decisión de Bruno sobre la ganancia de
/// [proveedorId] — cuánto retira ([retiroEfectivoCentavos] +
/// [retiroMercadoPagoCentavos], cada uno opcional por si solo usa un
/// medio) y el resto se retiene como colchón
/// ([gananciaCentavos] − lo retirado, nunca negativo: si Bruno decide
/// retirar más de lo que había, no hay colchón negativo). Mueve
/// `gananciaRevisadaFecha` a ahora para no volver a contar esta misma
/// ganancia mañana — no toca `corteReposicionFecha` ni `separadoCentavos`
/// (separar sigue siendo una decisión aparte, ver `separarProveedor`).
///
/// [fecha] default a ahora — mismo patrón que `separarProveedor`/`fecha`.
Future<void> revisarGananciaProveedor(
  AppDatabase db, {
  required int proveedorId,
  required int sesionCajaId,
  required int usuarioId,
  required int gananciaCentavos,
  int retiroEfectivoCentavos = 0,
  int retiroMercadoPagoCentavos = 0,
  DateTime? fecha,
}) async {
  if (retiroEfectivoCentavos > 0) {
    await registrarRetiroProveedor(
      db,
      proveedorId: proveedorId,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: retiroEfectivoCentavos,
      porMercadoPago: false,
    );
  }
  if (retiroMercadoPagoCentavos > 0) {
    await registrarRetiroProveedor(
      db,
      proveedorId: proveedorId,
      sesionCajaId: sesionCajaId,
      usuarioId: usuarioId,
      montoCentavos: retiroMercadoPagoCentavos,
      porMercadoPago: true,
    );
  }

  final retenido =
      gananciaCentavos - retiroEfectivoCentavos - retiroMercadoPagoCentavos;
  if (retenido > 0) {
    await retenerGanancia(
      db,
      proveedorId: proveedorId,
      montoCentavos: retenido,
    );
  }

  await (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(gananciaRevisadaFecha: Value(fecha ?? DateTime.now())),
  );
}

/// Aviso corto para la apertura de caja (Bruno separa con la persiana
/// baja): proveedores con algo sugerido para separar, con su monto.
Future<List<({String nombre, int montoCentavos})>> avisoASepararAlAbrir(
  AppDatabase db,
) async {
  final resumenes = await reposicionActual(db);
  return [
    for (final r in resumenes)
      if (r.sugeridoASepararCentavos > 0)
        (nombre: r.proveedor.nombre, montoCentavos: r.sugeridoASepararCentavos),
  ];
}

/// Congela lo pendiente sin separar como "separado", con la fecha de hoy, y
/// arranca de cero la próxima acumulación: mueve el corte a ahora y limpia
/// el arrastre. Lo que se venda después no toca este monto — se acumula
/// aparte, en `pendienteSinSepararCentavos`, hasta la próxima separación.
///
/// Se **suma** a lo que ya estuviera separado (si Bruno separa dos veces
/// antes de pagar) en vez de reemplazarlo — separar de nuevo no debería
/// poder hacer desaparecer plata ya apartada.
///
/// **El colchón se congela acá también, y se consume** (Regla 13): desde
/// que el colchón es ganancia real retenida (no una sugerencia teórica),
/// separar es el momento en que Bruno decide usarlo — "la única manera de
/// agregar más billete a ese colchón es que yo decida guardar las
/// ganancias también" implica que en algún momento se gasta, y ese momento
/// es pedirle de más al proveedor, que es exactamente lo que "separar"
/// representa. Vuelve a 0 acá; sigue creciendo desde cero hasta la próxima
/// vez que Bruno retenga ganancia de este proveedor.
///
/// [fecha] default a ahora — mismo patrón que `cerrarSesion`/`fechaCierre`
/// y `registrarPagoFijo`/`fecha`: hace falta poder pasarla explícita para
/// no depender del reloj real en los tests (el corte se compara contra
/// `ventas.fecha`, y drift guarda `DateTime` con precisión de segundo).
Future<void> separarProveedor(
  AppDatabase db, {
  required int proveedorId,
  DateTime? fecha,
}) async {
  final proveedor = await (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingle();
  final filas = await _lineasPorProveedorDesde(db, [proveedorId]);
  final parteMp = await _parteMpDeLineasDesde(db, proveedor.corteReposicionFecha);
  final resumen = _resumenDe(proveedor, filas[proveedorId] ?? const [], parteMp);
  final ahora = fecha ?? DateTime.now();

  await (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      separadoCentavos: Value(
        proveedor.separadoCentavos + resumen.sugeridoASepararCentavos,
      ),
      separadoMpCentavos: Value(
        proveedor.separadoMpCentavos + resumen.costoRealMpCentavos,
      ),
      separadoFecha: Value(ahora),
      corteReposicionFecha: Value(ahora),
      pendienteBaseCentavos: const Value(0),
      colchonReposicionCentavos: const Value(0),
    ),
  );
}

/// Registra el pago de lo separado. Si se pagó menos de lo separado, la
/// diferencia no se pierde: queda como `pendienteBaseCentavos` para el
/// próximo ciclo (Regla 5 extendida).
///
/// Efectivo y Mercado Pago mueven una caja real de la Plazoleta y quedan
/// como `MovimientoCaja` (tipo PAGO_PROVEEDOR) — MP se arquea como una caja
/// más desde que dejó de ser un campo suelto (`DECISIONES.md`), así que un
/// pago por MP tiene que bajar el saldo esperado igual que un pago en
/// efectivo baja el cajón. `cajaId` sigue siendo el cajón normal para los
/// dos (MP no es una fila de `Cajas`), y es `medioPagoId` el que separa uno
/// de otro para `gastosEnEfectivoDelDia`/`gastosPorMpDelDia` — mismo
/// criterio que `registrarPagoFijo`. Transferencia y cuenta corriente no
/// graban nada: esa plata nunca pasó por una caja de la app.
///
/// [montoCentavos] no puede superar lo separado — se valida en el diálogo
/// (el controlador ya tiene el monto separado en memoria), no acá.
///
/// [fecha] default a ahora — mismo patrón que `separarProveedor`/`fecha`,
/// para que los tests no dependan del reloj real.
///
/// [montoMpCentavos] (Bruno, 2026-09-26): la parte de [montoCentavos] que
/// sale de Mercado Pago — lo separado viene dividido entre cajón y MP
/// (`lib/domain/separacion_por_medio.dart`), y cada parte se registra por
/// el medio del que salió, con su propio movimiento, para que el arqueo de
/// cada caja baje lo que de verdad salió de ella. Solo para proveedores que
/// se pagan en efectivo o por MP: transferencia y cuenta corriente siguen
/// sin grabar nada. Null = como antes, todo por el medio del proveedor.
Future<void> pagarProveedor(
  AppDatabase db, {
  required int proveedorId,
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  DateTime? fecha,
  int? montoMpCentavos,
}) async {
  final proveedor = await (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingle();

  final pendienteBase = pendienteBaseTrasPago(
    separadoCentavos: proveedor.separadoCentavos,
    montoPagadoCentavos: montoCentavos,
  );

  await (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      separadoCentavos: const Value(0),
      separadoMpCentavos: const Value(0),
      separadoFecha: const Value(null),
      pendienteBaseCentavos: Value(pendienteBase),
      // Sin importar el medio: es la única fuente confiable de "desde
      // cuándo" para el período "Desde el último pago" (fase 13, pantalla
      // Proveedores) — Transferencia y Cuenta corriente no dejan rastro en
      // `movimientos_de_caja` (ver más abajo).
      ultimoPagoFecha: Value(fecha ?? DateTime.now()),
    ),
  );

  if (proveedor.medioPago != 'Efectivo' && proveedor.medioPago != 'Mercado Pago') return;

  final cajaNormal = await (db.select(
    db.cajas,
  )..where((c) => c.esLata.equals(false))).getSingle();
  final mpId = (await (db.select(
    db.mediosDePago,
  )..where((m) => m.esEfectivo.equals(false))).getSingle()).id;

  final porMp = montoMpCentavos ?? (proveedor.medioPago == 'Mercado Pago' ? montoCentavos : 0);
  final partes = [(montoCentavos - porMp, null), (porMp, mpId)];
  for (final (monto, medioPagoId) in partes) {
    if (monto <= 0) continue;
    await db
        .into(db.movimientosDeCaja)
        .insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionCajaId,
            cajaId: cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'PAGO_PROVEEDOR',
            montoCentavos: monto,
            proveedorId: Value(proveedorId),
            medioPagoId: Value(medioPagoId),
            // Sin esto, "SALIDAS/PAGOS" de la planilla (ítem 3) imprime el
            // monto sin decir de qué es — a diferencia de un gasto rápido,
            // que siempre pide un motivo.
            nota: Value('Pago a ${proveedor.nombre}'),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  }
}

/// Regla 13: retiene [montoCentavos] de la ganancia de este proveedor como
/// colchón — plata real que Bruno decide no llevarse del negocio, para
/// poder pedirle de más la próxima vez que separe (`separarProveedor`, que
/// es también el momento en que el colchón se gasta). Se **suma** al
/// colchón que ya hubiera, nunca lo reemplaza — mismo criterio que
/// `separarProveedor` con `separadoCentavos`.
Future<void> retenerGanancia(
  AppDatabase db, {
  required int proveedorId,
  required int montoCentavos,
}) async {
  final proveedor = await (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingle();
  await (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      colchonReposicionCentavos: Value(
        proveedor.colchonReposicionCentavos + montoCentavos,
      ),
    ),
  );
}

/// Regla 13: retira [montoCentavos] de ganancia de este proveedor fuera del
/// negocio — efectivo al bolsillo de Bruno, o de Mercado Pago a su cuenta
/// personal. No es una caja de la app, pero se registra igual como
/// `MovimientoCaja` tipo `RETIRO` (ver `tiposEgresoDeCaja`,
/// `repositorio_cierre.dart`): sin este rastro, el arqueo del día siguiente
/// marcaría un faltante por esta plata que salió sin que nadie la anotara.
///
/// [porMercadoPago] decide de qué saldo descuenta — no necesariamente el
/// medio de pago del proveedor (`Proveedor.medioPago` es cómo se le paga A
/// ÉL, no de dónde sale la ganancia que Bruno se lleva para sí mismo). Un
/// retiro parcial en cada medio son dos llamadas, una por medio.
Future<void> registrarRetiroProveedor(
  AppDatabase db, {
  required int proveedorId,
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  required bool porMercadoPago,
}) async {
  final proveedor = await (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingle();
  final cajaNormal = await (db.select(
    db.cajas,
  )..where((c) => c.esLata.equals(false))).getSingle();
  final medioPagoId = porMercadoPago
      ? (await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(false))).getSingle()).id
      : null;

  await db
      .into(db.movimientosDeCaja)
      .insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionCajaId,
          cajaId: cajaNormal.id,
          usuarioId: usuarioId,
          tipo: 'RETIRO',
          montoCentavos: montoCentavos,
          proveedorId: Value(proveedorId),
          medioPagoId: Value(medioPagoId),
          nota: Value('Retiro de ganancia — ${proveedor.nombre}'),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Colchón y medio de pago — vivía en el nivel 2 ("se tocan seguido, junto
/// con separar/pagar"), pero la segunda corrección post-revisión movió las
/// dos cosas (y separar/pagar) detrás de "Avanzado": el nivel 2 pasó a ser
/// puramente informativo ("es para mirar", Bruno), sin campos ni botones.
/// El colchón ahora se guarda desde `actualizarProveedorAvanzado` (mismo
/// motivo que el medio de pago); esta función queda igual para no romper lo
/// que ya la usa — es la misma regla que `historial_pedidos`, no tiene
/// sentido una migración solo para renombrar un camino de escritura que
/// sigue funcionando igual.
Future<void> actualizarProveedorNivel2(
  AppDatabase db, {
  required int proveedorId,
  required int colchonReposicionCentavos,
  required String medioPago,
}) {
  return (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      colchonReposicionCentavos: Value(colchonReposicionCentavos),
      medioPago: Value(medioPago),
    ),
  );
}

/// Nivel 3 "Avanzado": nombre, código, días de pedido/entrega,
/// activar/desactivar, medio de pago y colchón de reposición — todo lo que
/// no es "mirar los números" del proveedor pasó acá en la segunda
/// corrección post-revisión (Bruno: "es donde correspondían según los tres
/// niveles"). [codigo] es único (`Proveedores.codigo`, validado también en
/// el diálogo para un error legible antes de que la base lo rechace).
/// [nombre], [medioPago] y [colchonReposicionCentavos] se mantienen
/// opcionales para no romper un llamador que solo quiera tocar el resto de
/// los campos.
Future<void> actualizarProveedorAvanzado(
  AppDatabase db, {
  required int proveedorId,
  String? nombre,
  required String codigo,
  String? diaPedido,
  String? diaEntrega,
  required bool activo,
  String? medioPago,
  bool? cajaAparte,
  int? colchonReposicionCentavos,
}) {
  return (db.update(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).write(
    ProveedoresCompanion(
      nombre: nombre == null ? const Value.absent() : Value(nombre),
      codigo: Value(codigo),
      diaPedido: Value(diaPedido),
      diaEntrega: Value(diaEntrega),
      activo: Value(activo),
      medioPago: medioPago == null ? const Value.absent() : Value(medioPago),
      cajaAparte: cajaAparte == null ? const Value.absent() : Value(cajaAparte),
      colchonReposicionCentavos: colchonReposicionCentavos == null
          ? const Value.absent()
          : Value(colchonReposicionCentavos),
    ),
  );
}

/// Alta de un proveedor nuevo — la lista de 15 de `REGLAS-NEGOCIO.md` (16)
/// era la real al arrancar el negocio, no un límite del sistema: Bruno suma
/// proveedores con el tiempo igual que suma productos. [codigo] único, mismo
/// criterio de validación que [actualizarProveedorAvanzado] (el diálogo
/// confirma el conflicto buscando antes de mostrar el error de sqlite). El
/// resto arranca con los defaults de la tabla (medio Efectivo, activo,
/// colchón/separado en cero) — se termina de ajustar después desde
/// "Avanzado", no hace falta pedirlo todo en el alta.
Future<int> crearProveedor(
  AppDatabase db, {
  required String nombre,
  required String codigo,
  String? diaPedido,
  String? diaEntrega,
  String medioPago = 'Efectivo',
}) {
  return db
      .into(db.proveedores)
      .insert(
        ProveedoresCompanion.insert(
          nombre: nombre,
          codigo: codigo,
          diaPedido: Value(diaPedido),
          diaEntrega: Value(diaEntrega),
          medioPago: Value(medioPago),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

/// Productos de un proveedor, para la tabla del panel derecho de
/// Proveedores (segunda corrección post-revisión: "ver qué le comprás, a
/// cuánto, a cuánto lo vendés y cuánto sacás" — el corazón de la pantalla,
/// según Bruno). Solo productos activos: uno dado de baja no es algo que
/// hoy se le compre a este proveedor.
class ProductoDeProveedor {
  final int id;
  final String nombre;

  /// Costo/precio por unidad o por kilo según [esPesable] — ya resuelto acá
  /// para que la UI no tenga que preguntar de nuevo.
  final int? costoCentavos;
  final int? precioCentavos;

  /// Basis points (`markupBpDesdeCostoYPrecio`) — null si falta costo o
  /// precio, o si el costo es 0 (Regla 5: un producto sin costo cargado no
  /// se puede valorizar, y un costo en 0 daría un margen infinito).
  final int? margenBp;

  /// Para la barra de acento por rubro de la fila (`BarraCategoria`,
  /// `ui/comun/color_categoria.dart`) — rediseño de Proveedores 2026-09-25,
  /// quinta pasada: mismo lenguaje "bento con carácter" que ya usa Venta,
  /// antes ausente acá. Null si el producto no tiene categoría cargada.
  final int? categoriaId;

  /// Para la tarjeta de producto del "Lenguaje de diseño" (2026-09-26):
  /// de qué proveedor es (la lista cuenta productos y stock bajo por
  /// proveedor), y su stock contra el mínimo — unidades, o gramos si
  /// [esPesable].
  final int? proveedorId;
  final bool esPesable;
  final int stock;
  final int? stockMinimo;

  /// Para el buscador de Proveedores (contextual, 2026-09-28).
  final String? codigoBarras;

  const ProductoDeProveedor({
    required this.id,
    required this.nombre,
    required this.costoCentavos,
    required this.precioCentavos,
    required this.margenBp,
    required this.categoriaId,
    this.proveedorId,
    this.esPesable = false,
    this.stock = 0,
    this.stockMinimo,
    this.codigoBarras,
  });
}

ProductoDeProveedor _productoDeProveedorDesde(Producto p) =>
    ProductoDeProveedor(
      id: p.id,
      nombre: p.nombre,
      costoCentavos: p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos,
      precioCentavos: p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos,
      margenBp: _margenBpDeProducto(p),
      categoriaId: p.categoriaId,
      proveedorId: p.proveedorId,
      esPesable: p.esPesable,
      stock: p.esPesable ? (p.stockGramos ?? 0) : p.stock,
      stockMinimo: p.esPesable ? p.stockMinimoGramos : p.stockMinimo,
      codigoBarras: p.codigoBarras,
    );

/// Unidades (o gramos, en pesables) vendidas de cada producto desde
/// [desde], sin anuladas — "Vendidos" de la tarjeta de producto y el
/// "vendido hace poco" de `avisaPorStock`.
Future<Map<int, int>> vendidoPorProductoDesde(AppDatabase db, DateTime desde) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(db.ventas.fecha.isBiggerOrEqualValue(desde) & db.ventas.anuladaEn.isNull() & db.lineasDeVenta.productoId.isNotNull()))
      .get();
  final vendido = <int, int>{};
  for (final fila in filas) {
    final l = fila.readTable(db.lineasDeVenta);
    vendido[l.productoId!] = (vendido[l.productoId!] ?? 0) + (l.esPesable ? (l.gramos ?? 0) : (l.cantidad ?? 1));
  }
  return vendido;
}

Future<List<ProductoDeProveedor>> productosDeProveedor(
  AppDatabase db,
  int proveedorId,
) async {
  final productos =
      await (db.select(db.productos)
            ..where(
              (p) => p.proveedorId.equals(proveedorId) & p.activo.equals(true),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
          .get();
  return productos.map(_productoDeProveedorDesde).toList();
}

/// "Todos" (fase 13, primer ítem de `ListaMaestra` en Proveedores): el
/// catálogo entero, sin importar el proveedor. Sin "Varios" (Regla 5): es el
/// producto sentinela del botón de venta rápida, sin precio ni costo propio
/// — listarlo acá lo mostraría como "sin completar", cuando en realidad no
/// es un producto editable.
Future<List<ProductoDeProveedor>> productosTodos(AppDatabase db) async {
  final productos =
      await (db.select(db.productos)
            ..where((p) => p.activo.equals(true) & p.esVarios.equals(false) & p.esPromo.equals(false))
            ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
          .get();
  return productos.map(_productoDeProveedorDesde).toList();
}

/// "Sin proveedor" (fase 13, segundo ítem de `ListaMaestra` en Proveedores).
/// Mismo motivo que [productosTodos] para excluir "Varios".
Future<List<ProductoDeProveedor>> productosSinProveedor(AppDatabase db) async {
  final productos =
      await (db.select(db.productos)
            ..where(
              (p) =>
                  p.proveedorId.isNull() &
                  p.activo.equals(true) &
                  p.esVarios.equals(false) &
                  p.esPromo.equals(false),
            )
            ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
          .get();
  return productos.map(_productoDeProveedorDesde).toList();
}

int? _margenBpDeProducto(Producto p) {
  final costo = p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos;
  final precio = p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos;
  if (costo == null || costo == 0 || precio == null) return null;
  return markupBpDesdeCostoYPrecio(costo, precio);
}
