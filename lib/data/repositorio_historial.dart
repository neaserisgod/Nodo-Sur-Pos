// Lista de días cerrados (fase 9) y el detalle de ventas de cada uno.

import 'package:drift/drift.dart';

import '../domain/equilibrio.dart';
import 'database.dart';
import 'linea_venta_reconstruccion.dart';

class ResumenDia {
  final SesionCaja sesion;
  final String nombreEmpleado;
  final int totalVendidoCentavos;
  final int efectivoCentavos;
  final int mpCentavos;
  final int cigarrillosCentavos;
  final int diferenciaCentavos;

  const ResumenDia({
    required this.sesion,
    required this.nombreEmpleado,
    required this.totalVendidoCentavos,
    required this.efectivoCentavos,
    required this.mpCentavos,
    required this.cigarrillosCentavos,
    required this.diferenciaCentavos,
  });
}

Future<ResumenDia> _resumenDe(AppDatabase db, SesionCaja sesion) async {
  // Quién trabajó ese turno (Bruno, sesión del 31/08/2026: un turno es una
  // sesión completa) — sin esto, dos hojas del mismo día se ven idénticas
  // en la lista, que es justo lo que los turnos quieren distinguir.
  final usuario =
      await (db.select(db.usuarios)..where((u) => u.id.equals(sesion.usuarioAbrioId))).getSingle();
  final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesion.id))).get();
  final totalVendido = ventas.fold<int>(0, (acc, v) => acc + v.totalCentavos);

  final filasPagos = await (db.select(db.pagos).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.pagos.ventaId)),
    innerJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(db.pagos.medioPagoId)),
  ])
        ..where(db.ventas.sesionCajaId.equals(sesion.id)))
      .get();

  var efectivo = 0;
  var mp = 0;
  for (final fila in filasPagos) {
    final pago = fila.readTable(db.pagos);
    final medio = fila.readTable(db.mediosDePago);
    if (medio.esEfectivo) {
      efectivo += pago.montoCentavos;
    } else {
      mp += pago.montoCentavos;
    }
  }

  final filasCigarrillos = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(
          db.ventas.sesionCajaId.equals(sesion.id) & db.lineasDeVenta.tipoCigarrillo.isNotValue('ninguno'),
        ))
      .get();
  final cigarrillos = filasCigarrillos.fold<int>(0, (acc, fila) {
    final linea = fila.readTable(db.lineasDeVenta);
    return acc + linea.precioUnitarioCentavos * (linea.cantidad ?? 1);
  });

  return ResumenDia(
    sesion: sesion,
    nombreEmpleado: usuario.nombre,
    totalVendidoCentavos: totalVendido,
    efectivoCentavos: efectivo,
    mpCentavos: mp,
    cigarrillosCentavos: cigarrillos,
    diferenciaCentavos: sesion.diferenciaCentavos ?? 0,
  );
}

/// Todos los días cerrados, del más reciente al más viejo, con lo esencial
/// de cada uno para poder ver de un vistazo cuál dio mal.
Future<List<ResumenDia>> listarDias(AppDatabase db) async {
  final sesiones = await (db.select(db.sesionesDeCaja)
        ..where((s) => s.estado.equals('CERRADA'))
        ..orderBy([(s) => OrderingTerm.desc(s.fechaApertura)]))
      .get();

  final resultado = <ResumenDia>[];
  for (final sesion in sesiones) {
    resultado.add(await _resumenDe(db, sesion));
  }
  return resultado;
}

Future<List<FilaVenta>> ventasDelDia(AppDatabase db, int sesionId) {
  return (db.select(db.ventas)
        ..where((v) => v.sesionCajaId.equals(sesionId))
        ..orderBy([(v) => OrderingTerm.asc(v.fecha)]))
      .get();
}

Future<List<FilaLineaVenta>> lineasDeVenta(AppDatabase db, int ventaId) {
  return (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
}

Future<List<Pago>> pagosDeVenta(AppDatabase db, int ventaId) {
  return (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();
}

/// Una venta del detalle de un día, lista para mostrar.
class VentaDelDia {
  const VentaDelDia({required this.venta, required this.detalle, required this.medio});

  final FilaVenta venta;

  /// "2 Cerveza lata, 1 Papel higiénico" — qué se llevó.
  final String detalle;

  /// 'Ef', 'MP' o 'Mixto' (dos pagos).
  final String medio;

  bool get anulada => venta.anuladaEn != null;
}

/// Todo lo que muestra el detalle de un día cerrado ("Lenguaje de diseño",
/// mock `DetalleDia`, 2026-09-28): las ventas, lo cobrado por medio, la
/// ganancia y lo vendido por proveedor. Las anuladas vienen en la lista
/// (se ven tachadas, Regla 6: nunca se pierde el rastro) pero no suman.
class DetalleDelDia {
  const DetalleDelDia({
    required this.sesion,
    required this.nombreEmpleado,
    required this.ventas,
    required this.vendidoCentavos,
    required this.efectivoCentavos,
    required this.mpCentavos,
    required this.ventasEfectivo,
    required this.ventasMp,
    required this.gananciaCentavos,
    required this.costoCentavos,
    required this.vendidoSinCostoCentavos,
    required this.porProveedor,
  });

  final SesionCaja sesion;
  final String nombreEmpleado;

  /// De más nueva a más vieja.
  final List<VentaDelDia> ventas;
  final int vendidoCentavos;
  final int efectivoCentavos;
  final int mpCentavos;
  final int ventasEfectivo;
  final int ventasMp;
  final int gananciaCentavos;
  final int costoCentavos;
  final int vendidoSinCostoCentavos;

  /// De mayor a menor venta; "Sin proveedor" si hubo líneas sin proveedor.
  final List<({String nombre, int vendidoCentavos})> porProveedor;

  List<VentaDelDia> get validas => [for (final v in ventas) if (!v.anulada) v];
  List<VentaDelDia> get anuladas => [for (final v in ventas) if (v.anulada) v];
}

Future<DetalleDelDia> detalleDelDia(AppDatabase db, int sesionId) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final usuario = await (db.select(db.usuarios)..where((u) => u.id.equals(sesion.usuarioAbrioId))).getSingleOrNull();
  final ventas = await (db.select(db.ventas)
        ..where((v) => v.sesionCajaId.equals(sesionId))
        ..orderBy([(v) => OrderingTerm.desc(v.fecha)]))
      .get();
  final ids = ventas.map((v) => v.id).toList();
  final lineas = ids.isEmpty ? const <FilaLineaVenta>[] : await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.isIn(ids))).get();
  final pagos = ids.isEmpty ? const <Pago>[] : await (db.select(db.pagos)..where((p) => p.ventaId.isIn(ids))).get();
  final efectivoIds = {for (final m in await db.select(db.mediosDePago).get()) if (m.esEfectivo) m.id};
  final nombresProveedor = {for (final p in await db.select(db.proveedores).get()) p.id: p.nombre};

  final lineasPorVenta = <int, List<FilaLineaVenta>>{};
  for (final l in lineas) {
    lineasPorVenta.putIfAbsent(l.ventaId, () => []).add(l);
  }
  final pagosPorVenta = <int, List<Pago>>{};
  for (final p in pagos) {
    pagosPorVenta.putIfAbsent(p.ventaId, () => []).add(p);
  }

  String detalle(List<FilaLineaVenta> ls) => ls
      .map((l) => l.esPesable ? '${l.nombreProductoFoto} (${l.gramos} g)' : '${l.cantidad ?? 1} ${l.nombreProductoFoto}')
      .join(', ');

  var efectivo = 0, mp = 0, ventasEf = 0, ventasMp = 0;
  final lineasValidas = <FilaLineaVenta>[];
  final lista = <VentaDelDia>[];
  for (final v in ventas) {
    final ps = pagosPorVenta[v.id] ?? const <Pago>[];
    final medio = ps.length > 1 ? 'Mixto' : (ps.isEmpty || efectivoIds.contains(ps.single.medioPagoId) ? 'Ef' : 'MP');
    lista.add(VentaDelDia(venta: v, detalle: detalle(lineasPorVenta[v.id] ?? const []), medio: medio));
    if (v.anuladaEn != null) continue;
    lineasValidas.addAll(lineasPorVenta[v.id] ?? const []);
    var tocoEf = false, tocoMp = false;
    for (final p in ps) {
      if (efectivoIds.contains(p.medioPagoId)) {
        efectivo += p.montoCentavos;
        tocoEf = true;
      } else {
        mp += p.montoCentavos;
        tocoMp = true;
      }
    }
    if (tocoEf) ventasEf++;
    if (tocoMp) ventasMp++;
  }

  final ventaPorId = {for (final v in ventas) v.id: v};
  final reconstruidas = lineasValidas.map((l) => lineaParaReposicionDesde(l, venta: ventaPorId[l.ventaId])).toList();
  final ganancia = calcularGananciaBruta(lineas: reconstruidas);
  final porProv = <String, int>{};
  for (var i = 0; i < lineasValidas.length; i++) {
    final id = lineasValidas[i].proveedorIdFoto;
    final nombre = id == null ? 'Sin proveedor' : (nombresProveedor[id] ?? 'Sin proveedor');
    porProv[nombre] = (porProv[nombre] ?? 0) + reconstruidas[i].precioLineaCentavos;
  }
  final porProveedor = [for (final e in porProv.entries) (nombre: e.key, vendidoCentavos: e.value)]
    ..sort((a, b) => b.vendidoCentavos.compareTo(a.vendidoCentavos));

  return DetalleDelDia(
    sesion: sesion,
    nombreEmpleado: usuario?.nombre ?? '',
    ventas: lista,
    vendidoCentavos: lista.where((v) => !v.anulada).fold(0, (a, v) => a + v.venta.totalCentavos),
    efectivoCentavos: efectivo,
    mpCentavos: mp,
    ventasEfectivo: ventasEf,
    ventasMp: ventasMp,
    gananciaCentavos: ganancia.gananciaBrutaCentavos,
    costoCentavos: ganancia.ventaConCostoCentavos - ganancia.gananciaBrutaCentavos,
    vendidoSinCostoCentavos: ganancia.vendidoSinCostoCentavos,
    porProveedor: porProveedor,
  );
}
