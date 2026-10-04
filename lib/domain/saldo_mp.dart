// Saldo real de la cuenta de Mercado Pago para el cierre (etapa E, El dueño 2026-10-04): "se pide con un botón; al llegar llena
// el 'MP contado' y queda editable; las diferencias se avisan y se pueden cargar como gasto o ingreso por MP con un toque".
//
// Puro: sin Flutter, sin base, sin red. El saldo y los movimientos llegan ya leídos del reporte de Liquidaciones (vía el sitio).
// Cobros: ya los concilia `conciliarMp` (con los pagos de Mercado Pago); acá solo se miran los movimientos que NO son cobros —
// lo que salió de la cuenta o entró sin que sea una venta— contra lo que la app anotó como gasto o ingreso por MP.

import 'conciliacion_mp.dart';

class MovimientoSaldoMp {
  const MovimientoSaldoMp({
    required this.tipo,
    required this.descripcion,
    required this.creditoCentavos,
    required this.debitoCentavos,
    this.fecha,
    this.referencia,
    this.origen,
  });

  final DateTime? fecha;

  /// `release`, `payout`… tal como lo informa el reporte.
  final String tipo;
  final String descripcion;
  final int creditoCentavos;
  final int debitoCentavos;
  final String? referencia;
  final String? origen;

  bool get esEgreso => debitoCentavos > 0;
  bool get esIngreso => creditoCentavos > 0 && debitoCentavos == 0;

  /// Un cobro de un cliente: entra por crédito con descripción "payment". El mismo "payment" en un débito es un pago que
  /// HACE la cuenta (una factura, un proveedor) y sí es un egreso.
  bool get esCobro => esIngreso && descripcion == 'payment';
}

class SaldoMp {
  const SaldoMp({required this.disponibleCentavos, required this.movimientos, required this.hasta, this.aLiberarCentavos, this.truncado = false});

  /// Lo que hay disponible según la última fila del reporte.
  final int disponibleCentavos;

  /// Lo cobrado y todavía no liberado (no está en el reporte). Null si no se pudo calcular.
  final int? aLiberarCentavos;
  final List<MovimientoSaldoMp> movimientos;

  /// Hasta cuándo llega el reporte.
  final DateTime? hasta;
  final bool truncado;

  bool get aLiberarConocido => aLiberarCentavos != null;

  /// Todo lo que es de la cuenta: disponible + lo que MP todavía tiene por liberar. Es lo que se compara con el "MP contado".
  int get totalCentavos => disponibleCentavos + (aLiberarCentavos ?? 0);
  int get contadoSugeridoCentavos => totalCentavos;
}

/// Un gasto, pago o ingreso por MP que la app anotó en el turno, para emparejarlo con un movimiento del reporte.
class MovimientoMpEnApp {
  const MovimientoMpEnApp({required this.fecha, required this.montoCentavos, required this.esSalida});

  final DateTime fecha;
  final int montoCentavos;
  final bool esSalida;
}

class DiferenciasSaldoMp {
  const DiferenciasSaldoMp({required this.egresosSinRegistrar, required this.ingresosSinRegistrar, required this.ventasSinCobro});

  /// Salió plata de la cuenta y la app no lo tiene (un pago a un proveedor, una transferencia).
  final List<MovimientoSaldoMp> egresosSinRegistrar;

  /// Entró plata que no es un cobro y la app no lo tiene.
  final List<MovimientoSaldoMp> ingresosSinRegistrar;

  /// Ventas anotadas como cobradas por MP que no entraron a la cuenta.
  final List<PagoMpRegistrado> ventasSinCobro;

  bool get hayDiferencias => egresosSinRegistrar.isNotEmpty || ingresosSinRegistrar.isNotEmpty || ventasSinCobro.isNotEmpty;
}

/// Empareja cada movimiento del reporte (que no sea un cobro) con un gasto o ingreso de la app del MISMO monto y del mismo sentido
/// (el más cercano en el tiempo, cada uno se usa una sola vez). Lo que sobra es lo que hay que cargar o revisar.
/// [anuladasEnApp] son ventas anuladas por MP del turno: cubren una devolución (`refund`) del mismo monto, que si no
/// aparecería como un egreso sin registrar.
DiferenciasSaldoMp compararSaldoMp({
  required List<MovimientoSaldoMp> movimientos,
  required List<MovimientoMpEnApp> enApp,
  required List<PagoMpRegistrado> ventasSinCobro,
  List<MovimientoMpEnApp> anuladasEnApp = const [],
}) {
  final egresosDeCuenta = movimientos.where((m) => m.esEgreso && m.descripcion != 'refund').toList();
  final devolucionesDeCuenta = movimientos.where((m) => m.esEgreso && m.descripcion == 'refund').toList();
  final ingresosDeCuenta = movimientos.where((m) => m.esIngreso && !m.esCobro).toList();
  // Una devolución de la cuenta cubierta por una venta anulada de la app no es un egreso sin registrar; sin venta anulada que la
  // cubra, sí lo es.
  return DiferenciasSaldoMp(
    egresosSinRegistrar: [
      ..._sinCubrir(egresosDeCuenta, (m) => m.debitoCentavos, enApp.where((m) => m.esSalida).toList()),
      ..._sinCubrir(devolucionesDeCuenta, (m) => m.debitoCentavos, anuladasEnApp),
    ],
    ingresosSinRegistrar: _sinCubrir(ingresosDeCuenta, (m) => m.creditoCentavos, enApp.where((m) => !m.esSalida).toList()),
    ventasSinCobro: ventasSinCobro,
  );
}

/// Los [movimientos] que ningún candidato cubre. Cubrir = mismo monto; cada candidato se usa una sola vez y los pares más
/// cercanos en el tiempo se asignan primero (así dos movimientos iguales no se roban el candidato entre sí).
List<MovimientoSaldoMp> _sinCubrir(List<MovimientoSaldoMp> movimientos, int Function(MovimientoSaldoMp) monto, List<MovimientoMpEnApp> candidatos) {
  final pares = <({int m, int c, Duration d})>[];
  for (var i = 0; i < movimientos.length; i++) {
    for (var j = 0; j < candidatos.length; j++) {
      if (candidatos[j].montoCentavos != monto(movimientos[i])) continue;
      final f = movimientos[i].fecha;
      pares.add((m: i, c: j, d: f == null ? const Duration(days: 3650) : candidatos[j].fecha.difference(f).abs()));
    }
  }
  pares.sort((a, b) => a.d.compareTo(b.d));
  final movCubiertos = <int>{};
  final candUsados = <int>{};
  for (final p in pares) {
    if (movCubiertos.contains(p.m) || candUsados.contains(p.c)) continue;
    movCubiertos.add(p.m);
    candUsados.add(p.c);
  }
  return [
    for (var i = 0; i < movimientos.length; i++)
      if (!movCubiertos.contains(i)) movimientos[i],
  ];
}
