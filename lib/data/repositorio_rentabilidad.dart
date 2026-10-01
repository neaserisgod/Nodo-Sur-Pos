// Arma los insumos del estado de resultados (`domain/rentabilidad.dart`) desde
// la base. Nada de cuentas acá: solo sumar lo que ya está registrado, con el
// mismo criterio que el resto (ventas no anuladas, precio neto de descuento,
// costo-foto) para que este número nunca discuta con Equilibrio.

import 'package:drift/drift.dart';

import '../domain/rentabilidad.dart';
import 'database.dart';
import 'repositorio_equilibrio.dart';

(DateTime, DateTime) _rango(String mesAnio) {
  final partes = mesAnio.split('-');
  final anio = int.parse(partes[0]);
  final mes = int.parse(partes[1]);
  return (DateTime(anio, mes), DateTime(anio, mes + 1));
}

Future<int> _sumaMovimientos(
  AppDatabase db,
  String mesAnio, {
  required String tipo,
  required bool soloSinGastoFijo,
}) async {
  final (inicio, fin) = _rango(mesAnio);
  final m = db.movimientosDeCaja;
  final query = db.selectOnly(m)
    ..addColumns([m.montoCentavos.sum()])
    ..where(
      m.tipo.equals(tipo) &
          m.fecha.isBiggerOrEqualValue(inicio) &
          m.fecha.isSmallerThanValue(fin) &
          (soloSinGastoFijo ? m.gastoFijoId.isNull() : const Constant(true)),
    );
  final fila = await query.getSingle();
  return fila.read(m.montoCentavos.sum()) ?? 0;
}

/// Estado de resultados de [mesAnio] ("YYYY-MM").
///
/// [sueldoGastoFijoId] es el concepto de gasto fijo que representa el sueldo
/// del dueño (por ejemplo uno llamado "Sueldo del dueño"): su monto del mes se
/// toma como sueldo objetivo y se saca de los fijos, para no contarlo dos
/// veces. Sin él, el sueldo objetivo es 0 y el estado lo advierte.
///
/// Los fijos sin monto cargado NO se suman como 0: el estado queda incompleto
/// (`fijosCompletos: false`) y lo dice.
Future<EstadoDeResultados> estadoDeResultadosDelMes(
  AppDatabase db,
  String mesAnio, {
  int? sueldoGastoFijoId,
  int reservaCentavos = 0,
}) async {
  final ganancia = await gananciaBrutaDelMes(db, mesAnio);
  final fijos = await fijosDelMes(db, mesAnio);

  var gastosFijos = 0;
  var sueldo = 0;
  for (final c in fijos.conceptos) {
    final monto = c.montoCentavos;
    if (monto == null) continue;
    if (sueldoGastoFijoId != null && c.concepto.id == sueldoGastoFijoId) {
      sueldo += monto;
    } else {
      gastosFijos += monto;
    }
  }

  final variables = await _sumaMovimientos(db, mesAnio, tipo: 'GASTO', soloSinGastoFijo: true);
  final retiros = await _sumaMovimientos(db, mesAnio, tipo: 'RETIRO', soloSinGastoFijo: false);

  return calcularEstadoDeResultados(
    DatosDelMes(
      ventasNetasCentavos: ganancia.ventaConCostoCentavos + ganancia.vendidoSinCostoCentavos,
      ventasConCostoCentavos: ganancia.ventaConCostoCentavos,
      gananciaBrutaCentavos: ganancia.gananciaBrutaCentavos,
      gastosFijosCentavos: gastosFijos,
      gastosVariablesCentavos: variables,
      sueldoObjetivoCentavos: sueldo,
      retirosDelMesCentavos: retiros,
      reservaCentavos: reservaCentavos,
      fijosCompletos: fijos.faltantes.isEmpty,
    ),
  );
}
