// Arma los datos de la planilla "Control diario de caja" para UN día —
// histórico o normal, no hay diferencia: cada línea de venta ya guarda su
// nombre (texto libre o producto real, según cómo se cargó) en
// `nombreProductoFoto`, así que se recorre igual en los dos casos.
//
// Un renglón por venta, no por línea de producto (corrección de el dueño,
// ítem 3): "pago mixto: un renglón en cada grilla" quiere decir eso
// literal, un renglón por grilla con la parte que le tocó a cada medio —
// no cada línea de producto repartida proporcionalmente entre las dos.
// No hace falta saber qué línea se pagó con qué medio (esa información no
// existe): alcanza con el total de cada `Pago` de la venta, uno por
// renglón. DETALLE lista los productos de la venta; PROV lleva todas las
// letras que correspondan si hay más de un proveedor ("Múltiple: poner
// todas las letras", papel viejo).

import 'package:drift/drift.dart';

import '../domain/caja.dart';
import 'database.dart';
import 'repositorio_cierre.dart' show pagosALataDelDia, reposicionDelDia, tiposEgresoDeCaja;
import 'repositorio_historial.dart';

class RenglonPlanillaCalculado {
  final int montoCentavos;
  final DateTime hora;

  /// Los productos de la venta, unidos con ", " — no una línea sola.
  final String detalle;

  /// Las letras de proveedor de la venta (Regla 16), unidas con "," si hay
  /// más de una — null si ninguna línea tenía proveedor (o eran todas
  /// cigarrillos, que nunca llevan letra).
  final String? letraProveedor;

  const RenglonPlanillaCalculado({
    required this.montoCentavos,
    required this.hora,
    required this.detalle,
    required this.letraProveedor,
  });
}

class GastoDia {
  final int montoCentavos;
  final String motivo;
  final bool deLata;

  const GastoDia({required this.montoCentavos, required this.motivo, required this.deLata});
}

class DatosPlanillaDia {
  final SesionCaja sesion;
  final String nombreEmpleado;

  /// Solo si quien cerró no es quien abrió (El dueño: un turno normalmente lo
  /// entrega y recibe la misma persona, pero el modelo permite lo
  /// contrario) — reemplaza a las dos firmas del papel viejo.
  final String? nombreCerro;

  final List<RenglonPlanillaCalculado> renglonesEfectivo;
  final List<RenglonPlanillaCalculado> renglonesMp;
  final int totalEfectivoCentavos;
  final int totalMpCentavos;
  final List<GastoDia> gastos;
  final int quedaEnCajonCentavos;

  /// Pagos a Distribuidora de Cigarrillos con origen lata (Regla 6) — la línea "(-) Pagos
  /// a Distribuidora de Cigarrillos" del arqueo propio de la lata (ítem 3).
  final int pagosALataCentavos;

  /// "Varios" + alta rápida sin costo completado, vendido este día (Regla
  /// 5: el cierre tiene que mostrar cuánto se vendió sin costo, para que
  /// se vea la reposición que no se está calculando).
  final int vendidoSinCostoCentavos;

  const DatosPlanillaDia({
    required this.sesion,
    required this.nombreEmpleado,
    required this.nombreCerro,
    required this.renglonesEfectivo,
    required this.renglonesMp,
    required this.totalEfectivoCentavos,
    required this.totalMpCentavos,
    required this.gastos,
    required this.quedaEnCajonCentavos,
    required this.pagosALataCentavos,
    required this.vendidoSinCostoCentavos,
  });
}

void _agregarRenglon(
  List<RenglonPlanillaCalculado> destino, {
  required int montoCentavos,
  required DateTime hora,
  required String detalle,
  required String? letraProveedor,
}) {
  if (montoCentavos <= 0) return;
  destino.add(RenglonPlanillaCalculado(
    montoCentavos: montoCentavos,
    hora: hora,
    detalle: detalle,
    letraProveedor: letraProveedor,
  ));
}

Future<DatosPlanillaDia> armarDatosPlanilla(AppDatabase db, int sesionId) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final usuario = await (db.select(db.usuarios)..where((u) => u.id.equals(sesion.usuarioAbrioId))).getSingle();
  String? nombreCerro;
  if (sesion.usuarioCerroId != null && sesion.usuarioCerroId != sesion.usuarioAbrioId) {
    nombreCerro = (await (db.select(db.usuarios)..where((u) => u.id.equals(sesion.usuarioCerroId!))).getSingle()).nombre;
  }
  final proveedores = {for (final p in await db.select(db.proveedores).get()) p.id: p.codigo};
  final medios = {for (final m in await db.select(db.mediosDePago).get()) m.id: m};

  final renglonesEfectivo = <RenglonPlanillaCalculado>[];
  final renglonesMp = <RenglonPlanillaCalculado>[];

  final ventas = await ventasDelDia(db, sesionId);
  for (final venta in ventas) {
    final lineas = await lineasDeVenta(db, venta.id);
    var detalle = lineas.map((l) => l.nombreProductoFoto).join(', ');
    // Sin esto, el renglón del recargo (ej. $300 de un cigarrillo de
    // $4.500) se lee como si se hubiera vendido un Marlboro a $300 (El dueño,
    // revisión del demo del ítem 3) — el recargo es parte de la misma
    // venta, no otro producto, así que se aclara en el mismo DETALLE.
    if (venta.recargoCigarrillosCentavos > 0) detalle += ' + recargo QR';
    final letras = <String>{};
    for (final linea in lineas) {
      if (linea.tipoCigarrillo != 'ninguno') continue; // cigarrillos: sin letra
      final letra = proveedores[linea.proveedorIdFoto];
      if (letra != null) letras.add(letra);
    }
    final letraCombinada = letras.isEmpty ? null : (letras.toList()..sort()).join(',');

    final pagos = await pagosDeVenta(db, venta.id);
    for (final pago in pagos) {
      final destino = medios[pago.medioPagoId]!.esEfectivo ? renglonesEfectivo : renglonesMp;
      _agregarRenglon(
        destino,
        montoCentavos: pago.montoCentavos,
        hora: venta.fecha,
        detalle: detalle,
        letraProveedor: letraCombinada,
      );
    }
  }

  final totalEfectivo = renglonesEfectivo.fold<int>(0, (acc, r) => acc + r.montoCentavos);
  final totalMp = renglonesMp.fold<int>(0, (acc, r) => acc + r.montoCentavos);

  final movimientosGasto = await (db.select(db.movimientosDeCaja)
        ..where((m) => m.sesionCajaId.equals(sesionId) & m.tipo.isIn(tiposEgresoDeCaja)))
      .get();
  final cajas = {for (final c in await db.select(db.cajas).get()) c.id: c};
  final gastos = movimientosGasto
      .map((m) => GastoDia(
            montoCentavos: m.montoCentavos,
            motivo: m.nota ?? '',
            deLata: cajas[m.cajaId]!.esLata,
          ))
      .toList();

  final quedaEnCajon = quedaEnCajonCentavos(
    efectivoContadoCentavos: sesion.efectivoContadoCentavos ?? 0,
    lataSeparadoCentavos: sesion.lataSeparadoCentavos ?? 0,
  );
  final pagosALata = await pagosALataDelDia(db, sesionId);
  final vendidoSinCosto = (await reposicionDelDia(db, sesionId)).vendidoSinCostoCentavos;

  return DatosPlanillaDia(
    sesion: sesion,
    nombreEmpleado: usuario.nombre,
    nombreCerro: nombreCerro,
    renglonesEfectivo: renglonesEfectivo,
    renglonesMp: renglonesMp,
    totalEfectivoCentavos: totalEfectivo,
    totalMpCentavos: totalMp,
    gastos: gastos,
    quedaEnCajonCentavos: quedaEnCajon,
    pagosALataCentavos: pagosALata,
    vendidoSinCostoCentavos: vendidoSinCosto,
  );
}
