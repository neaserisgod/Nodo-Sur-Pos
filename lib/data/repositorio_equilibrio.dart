// Rentabilidad y equilibrio (fase 7, Regla 12): ganancia real del mes, carga
// mínima de fijos (concepto + monto por mes, para que un aumento de alquiler
// no reescriba meses anteriores) y fijos pendientes del mes (Regla 13, la
// pantalla de "revisar cierre y separar" la muestra junto al retiro).
//
// "Avisar antes que inventar": cualquier número que dependa de los fijos del
// mes (equilibrio, fijos pendientes, reserva diaria) es `null` si falta
// cargar el monto de algún concepto activo ese mes — nunca se completa con
// un valor supuesto.

import 'package:drift/drift.dart';

import '../domain/equilibrio.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'linea_venta_reconstruccion.dart';

String mesAnioDe(DateTime fecha) => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

(DateTime inicio, DateTime finExclusiva) _rangoMes(String mesAnio) {
  final partes = mesAnio.split('-');
  final anio = int.parse(partes[0]);
  final mes = int.parse(partes[1]);
  return (DateTime(anio, mes), DateTime(anio, mes + 1));
}

int _diasDelMes(String mesAnio) {
  final (inicio, fin) = _rangoMes(mesAnio);
  return fin.difference(inicio).inDays;
}

class GastoFijoDelMes {
  final GastoFijo concepto;
  final int? montoCentavos;

  const GastoFijoDelMes({required this.concepto, required this.montoCentavos});
}

class ResumenFijosDelMes {
  final List<GastoFijoDelMes> conceptos;

  /// Null si falta cargar el monto de algún concepto activo — ver [faltantes].
  final int? total;
  final List<String> faltantes;

  const ResumenFijosDelMes({required this.conceptos, required this.total, required this.faltantes});
}

Future<ResumenFijosDelMes> fijosDelMes(AppDatabase db, String mesAnio) async {
  final conceptos = await (db.select(db.gastosFijos)..where((g) => g.activo.equals(true))).get();
  final montos = await (db.select(db.gastosFijosMontos)..where((m) => m.mesAnio.equals(mesAnio))).get();
  final montoPorConcepto = {for (final m in montos) m.gastoFijoId: m.montoCentavos};

  final conceptosDelMes = <GastoFijoDelMes>[];
  final faltantes = <String>[];
  var total = 0;
  for (final c in conceptos) {
    final monto = montoPorConcepto[c.id];
    conceptosDelMes.add(GastoFijoDelMes(concepto: c, montoCentavos: monto));
    if (monto == null) {
      faltantes.add(c.nombre);
    } else {
      total += monto;
    }
  }

  return ResumenFijosDelMes(
    conceptos: conceptosDelMes,
    total: faltantes.isEmpty ? total : null,
    faltantes: faltantes,
  );
}

Future<int> fijosPagadosDelMes(AppDatabase db, String mesAnio) async {
  final (inicio, fin) = _rangoMes(mesAnio);
  final query = db.selectOnly(db.movimientosDeCaja)
    ..addColumns([db.movimientosDeCaja.montoCentavos.sum()])
    ..where(
      db.movimientosDeCaja.gastoFijoId.isNotNull() &
          db.movimientosDeCaja.fecha.isBiggerOrEqualValue(inicio) &
          db.movimientosDeCaja.fecha.isSmallerThanValue(fin),
    );
  final fila = await query.getSingle();
  return fila.read(db.movimientosDeCaja.montoCentavos.sum()) ?? 0;
}

Future<ResultadoGananciaBruta> gananciaBrutaDelMes(AppDatabase db, String mesAnio) async {
  final (inicio, fin) = _rangoMes(mesAnio);
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(
          db.ventas.fecha.isBiggerOrEqualValue(inicio) &
              db.ventas.fecha.isSmallerThanValue(fin) &
              db.ventas.anuladaEn.isNull(),
        ))
      .get();

  final lineas = filas.map((fila) => lineaParaReposicionDesde(fila.readTable(db.lineasDeVenta), venta: fila.readTable(db.ventas))).toList();
  return calcularGananciaBruta(lineas: lineas);
}

Future<void> cargarMontoDelMes(
  AppDatabase db, {
  required int gastoFijoId,
  required String mesAnio,
  required int montoCentavos,
}) {
  final companion = GastosFijosMontosCompanion.insert(
    gastoFijoId: gastoFijoId,
    mesAnio: mesAnio,
    montoCentavos: montoCentavos,
  );
  return db.into(db.gastosFijosMontos).insert(
        companion,
        onConflict: DoUpdate(
          (_) => companion,
          target: [db.gastosFijosMontos.gastoFijoId, db.gastosFijosMontos.mesAnio],
        ),
      );
}

Future<int> crearConcepto(AppDatabase db, String nombre) {
  return db.into(db.gastosFijos).insert(GastosFijosCompanion.insert(nombre: nombre));
}

/// [pagadoConMp]: mismo criterio que el gasto rápido de venta — `cajaId`
/// sigue siendo el cajón normal (MP no es una fila de `Cajas`), pero se
/// marca con `medioPagoId` para que `gastosEnEfectivoDelDia` lo excluya del
/// efectivo esperado y `gastosPorMpDelDia` lo reste del MP esperado.
///
/// [fecha] default a ahora — mismo patrón que `cerrarSesion`/`fechaCierre`
/// (`repositorio_cierre.dart`). Hace falta poder pasarla explícita porque
/// El dueño paga el alquiler un día y lo carga en el sistema otro (a veces
/// cruzando de mes): sin esto, `fijosPagadosDelMes` filtra por la fecha real
/// del movimiento y el pago cae en el mes equivocado, descuadrando fijos
/// pendientes y el retiro de ese mes.
Future<void> registrarPagoFijo(
  AppDatabase db, {
  required int gastoFijoId,
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  bool pagadoConMp = false,
  DateTime? fecha,
}) async {
  final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
  final medioPagoId = pagadoConMp
      ? (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id
      : null;
  await db.into(db.movimientosDeCaja).insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionCajaId,
          cajaId: cajaNormal.id,
          usuarioId: usuarioId,
          tipo: 'GASTO',
          montoCentavos: montoCentavos,
          fecha: Value(fecha ?? DateTime.now()),
          gastoFijoId: Value(gastoFijoId),
          medioPagoId: Value(medioPagoId),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Fijos pendientes del mes = fijos del mes − fijos ya pagados, nunca
/// negativo. Null si los fijos del mes están incompletos ("avisar antes que
/// inventar") — antes vivía duplicada acá (dentro del extinto
/// `retiroSugeridoDelMes`, Regla 13 vieja) y en `equilibrio_controlador.dart`;
/// ahora es una sola función (Regla 3) que alimenta la pantalla de
/// Equilibrio y la de "revisar cierre y separar" (Regla 13 nueva).
Future<int?> fijosPendientesDelMes(AppDatabase db, String mesAnio) async {
  final fijos = await fijosDelMes(db, mesAnio);
  if (fijos.total == null) return null;

  final pagados = await fijosPagadosDelMes(db, mesAnio);
  final pendientes = fijos.total! - pagados;
  return pendientes < 0 ? 0 : pendientes;
}

/// Venta diaria de equilibrio y reserva diaria de referencia, ambas con
/// [mesAnio] usando su cantidad real de días — o null si los fijos del mes
/// están incompletos, mismo criterio en toda esta pantalla.
Future<({int? ventaDiaria, int? reservaDiaria})> referenciasDiarias(
  AppDatabase db,
  String mesAnio,
) async {
  final fijos = await fijosDelMes(db, mesAnio);
  final total = fijos.total;
  if (total == null) return (ventaDiaria: null, reservaDiaria: null);

  final ganancia = await gananciaBrutaDelMes(db, mesAnio);
  final dias = _diasDelMes(mesAnio);
  final margen = ganancia.margenPonderado;

  final ventaDiaria = margen == null
      ? null
      : ventaDiariaDeEquilibrio(fijosMensualesCentavos: total, margenPonderado: margen, diasDelMes: dias);

  return (
    ventaDiaria: ventaDiaria,
    reservaDiaria: reservaDiariaFijosCentavos(fijosMensualesCentavos: total, diasDelMes: dias),
  );
}
