// Conciliación de Mercado Pago (El dueño, 2026-10-03: "generar el cierre de caja
// desde el sistema... a rajatabla"): lo que Mercado Pago dice que entró a la
// cuenta en el turno contra lo que la app registró como cobrado por Mercado
// Pago. Antes la "Diferencia MP" del cierre mezclaba tres cosas sin poder
// separarlas: comisiones (casi siempre), cobros que no se anotaron en la app y
// ventas anotadas como Mercado Pago que nunca se cobraron. Acá se separan.
//
// Puro: sin Flutter, sin base, sin red. Los cobros llegan ya leídos.

/// Un cobro tal como lo informa Mercado Pago (vía el sitio, `/api/mp/cobros`).
class CobroMp {
  const CobroMp({
    required this.id,
    required this.estado,
    required this.fecha,
    required this.montoCentavos,
    required this.devueltoCentavos,
    required this.comisionCentavos,
    required this.netoCentavos,
    this.medio,
    this.metodo,
    this.referencia,
  });

  final String id;
  final String? estado;
  final DateTime? fecha;
  final int montoCentavos;
  final int devueltoCentavos;
  final int comisionCentavos;
  final int netoCentavos;

  /// `account_money` (QR / dinero en cuenta), `debit_card`, `credit_card`, `bank_transfer`…
  final String? medio;
  final String? metodo;
  final String? referencia;

  /// Rechazados, cancelados y pendientes no son plata que entró.
  bool get cobrado => estadosCobradosMp.contains(estado);

  /// Lo que quedó cobrado después de devoluciones (antes de comisión).
  int get cobradoNetoDeDevolucionesCentavos => montoCentavos - devueltoCentavos;
}

const estadosCobradosMp = {'approved', 'partially_refunded', 'refunded', 'charged_back'};

/// Un pago de una venta que la app registró como Mercado Pago.
class PagoMpRegistrado {
  const PagoMpRegistrado({required this.ventaId, required this.fecha, required this.montoCentavos, this.canal});

  final int ventaId;
  final DateTime fecha;
  final int montoCentavos;
  final String? canal;
}

class ConciliacionMp {
  const ConciliacionMp({
    required this.cantidadCobros,
    required this.brutoCentavos,
    required this.devueltoCentavos,
    required this.comisionCentavos,
    required this.netoCentavos,
    required this.noCobrados,
    required this.registradoCentavos,
    required this.cobrosSinVenta,
    required this.ventasSinCobro,
    required this.truncado,
  });

  final int cantidadCobros;
  final int brutoCentavos;
  final int devueltoCentavos;
  final int comisionCentavos;

  /// Lo que de verdad entró a la cuenta: bruto − devoluciones − comisiones.
  final int netoCentavos;

  /// Rechazados / cancelados / pendientes que Mercado Pago informa en el turno (no suman).
  final int noCobrados;

  /// Lo que la app registró como cobrado por Mercado Pago en el turno (ventas no anuladas).
  final int registradoCentavos;

  /// Cobros que entraron a Mercado Pago y no tienen una venta de la app con el mismo monto.
  final List<CobroMp> cobrosSinVenta;

  /// Ventas registradas como Mercado Pago sin un cobro de Mercado Pago con el mismo monto.
  final List<PagoMpRegistrado> ventasSinCobro;

  /// Mercado Pago tenía más cobros de los que se pudieron leer: los totales quedan cortos.
  final bool truncado;

  /// Cobrado (sin devoluciones) según Mercado Pago menos lo registrado en la app.
  /// Cero = cada peso que entró está anotado; positivo = entró plata sin venta; negativo = ventas sin cobro.
  int get diferenciaCobrosCentavos => brutoCentavos - devueltoCentavos - registradoCentavos;

  /// El esperado de Mercado Pago del cierre, pero con lo que de verdad entró en lugar de lo registrado: si este
  /// número coincide con lo contado en la app de Mercado Pago, la "Diferencia MP" era solo comisiones y devoluciones.
  int esperadoRealCentavos(int mpEsperadoSistemaCentavos) => mpEsperadoSistemaCentavos - registradoCentavos + netoCentavos;
}

/// Empareja cada pago registrado con un cobro de Mercado Pago del MISMO monto (el más cercano en el tiempo, cada cobro
/// se usa una sola vez). Lo que sobra de cada lado es lo que hay que mirar.
ConciliacionMp conciliarMp({
  required List<CobroMp> cobros,
  required List<PagoMpRegistrado> registrados,
  bool truncado = false,
}) {
  final cobrados = cobros.where((c) => c.cobrado).toList();
  final libres = List<CobroMp>.of(cobrados);
  final sinCobro = <PagoMpRegistrado>[];

  final ordenados = List<PagoMpRegistrado>.of(registrados)..sort((a, b) => a.fecha.compareTo(b.fecha));
  for (final r in ordenados) {
    CobroMp? mejor;
    var mejorDistancia = 0;
    for (final c in libres) {
      if (c.montoCentavos != r.montoCentavos) continue;
      final d = c.fecha == null ? 1 << 40 : c.fecha!.difference(r.fecha).inSeconds.abs();
      if (mejor == null || d < mejorDistancia) {
        mejor = c;
        mejorDistancia = d;
      }
    }
    if (mejor == null) {
      sinCobro.add(r);
    } else {
      libres.remove(mejor);
    }
  }

  var bruto = 0, devuelto = 0, comision = 0, neto = 0;
  for (final c in cobrados) {
    bruto += c.montoCentavos;
    devuelto += c.devueltoCentavos;
    comision += c.comisionCentavos;
    neto += c.netoCentavos;
  }
  return ConciliacionMp(
    cantidadCobros: cobrados.length,
    brutoCentavos: bruto,
    devueltoCentavos: devuelto,
    comisionCentavos: comision,
    netoCentavos: neto,
    noCobrados: cobros.length - cobrados.length,
    registradoCentavos: registrados.fold(0, (a, r) => a + r.montoCentavos),
    // Un cobro devuelto entero no es "plata sin venta": se fue igual que vino.
    cobrosSinVenta: libres.where((c) => c.cobradoNetoDeDevolucionesCentavos > 0).toList(),
    ventasSinCobro: sinCobro,
    truncado: truncado,
  );
}
