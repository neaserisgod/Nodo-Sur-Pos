// Avisos de Mercado Pago para la campanita (etapa D, El dueño 2026-10-04): un cobro que entró a la cuenta y no tiene venta en la
// app, un contracargo, un reclamo. Solo avisa: no toca la caja ni el stock (la plata de un contracargo la resuelve Mercado Pago).
//
// Puro: sin Flutter, sin base, sin red. Los avisos llegan del sitio (`/api/mp/avisos` y el aviso en vivo); acá se cruzan con las
// ventas y órdenes de ESTE equipo para decidir cuáles mostrar. La regla de cruce de "cobro sin venta" es la misma del cierre
// (`conciliarMp`): mismo monto, el más cercano en el tiempo, cada venta se usa una sola vez.

import 'conciliacion_mp.dart';
import 'dinero.dart';

enum TipoAvisoMp { cobro, contracargo, reclamo }

class AvisoMp {
  const AvisoMp({
    required this.idServidor,
    required this.tipo,
    required this.mpId,
    required this.creado,
    this.pagoId,
    this.montoCentavos,
    this.referencia,
    this.estado,
    this.detalle,
    this.fecha,
    this.visto = false,
  });

  /// El id que le puso el sitio: crece con cada aviso, y es el cursor con el que se piden los que faltan.
  final int idServidor;
  final TipoAvisoMp tipo;

  /// Id del cobro, contracargo o reclamo en Mercado Pago. Un contracargo que cambia manda otro aviso con el mismo [mpId].
  final String mpId;
  final String? pagoId;
  final int? montoCentavos;

  /// El `externalReference` de la orden de la Point, si el cobro salió de una.
  final String? referencia;
  final String? estado;
  final String? detalle;

  /// Cuándo pasó el cobro (o se abrió el reclamo), según Mercado Pago.
  final DateTime? fecha;

  /// Cuándo se enteró el sitio.
  final DateTime creado;
  final bool visto;
}

/// Una orden de la Point de este equipo (`ordenes_cobro_pendientes`): con [ventaId] si el cobro terminó en venta.
class OrdenConocida {
  const OrdenConocida({required this.referencia, this.ventaId});

  final String referencia;
  final int? ventaId;
}

/// Una venta de la app cobrada por Mercado Pago.
class VentaMp {
  const VentaMp({required this.ventaId, required this.fecha, required this.montoCentavos, this.numero});

  final int ventaId;
  final String? numero;
  final DateTime fecha;
  final int montoCentavos;
}

class AvisoParaMostrar {
  const AvisoParaMostrar({required this.aviso, required this.titulo, required this.texto, this.ventaId, this.ventaNumero});

  final AvisoMp aviso;
  final String titulo;
  final String texto;
  final int? ventaId;
  final String? ventaNumero;

  TipoAvisoMp get tipo => aviso.tipo;
}

/// La venta se graba al terminar de cobrar, unos segundos después de que Mercado Pago avisa el cobro: sin esta espera, cada
/// cobro normal parpadearía como "sin venta".
const esperaAvisoCobro = Duration(minutes: 5);

List<AvisoParaMostrar> avisosParaMostrar({
  required List<AvisoMp> avisos,
  required List<OrdenConocida> ordenes,
  required List<VentaMp> ventas,
  required DateTime ahora,
  Duration espera = esperaAvisoCobro,
}) {
  final ventaPorId = {for (final v in ventas) v.ventaId: v};
  final ventaDeReferencia = <String, int>{
    for (final o in ordenes)
      if (o.ventaId != null) o.referencia: o.ventaId!,
  };
  final resultado = <AvisoParaMostrar>[];

  // --- cobros: lo que no tiene venta
  final cobros = avisos.where((a) => a.tipo == TipoAvisoMp.cobro && !a.visto && ahora.difference(a.creado) >= espera).toList();
  final ventasLibres = List<VentaMp>.of(ventas);
  final porCruzar = <AvisoMp>[];
  for (final c in cobros) {
    final ventaId = c.referencia == null ? null : ventaDeReferencia[c.referencia];
    if (ventaId != null) {
      // Cobro de una orden de la app que terminó en venta: esa venta ya está contada, que no tape a otro cobro del mismo monto.
      ventasLibres.removeWhere((v) => v.ventaId == ventaId);
    } else if (c.montoCentavos == null) {
      resultado.add(_deCobro(c)); // sin monto no hay con qué cruzar
    } else {
      porCruzar.add(c);
    }
  }
  final conciliacion = conciliarMp(
    cobros: [
      for (final c in porCruzar)
        CobroMp(
          id: '${c.idServidor}',
          estado: 'approved',
          fecha: c.fecha ?? c.creado,
          montoCentavos: c.montoCentavos!,
          devueltoCentavos: 0,
          comisionCentavos: 0,
          netoCentavos: c.montoCentavos!,
        ),
    ],
    registrados: [for (final v in ventasLibres) PagoMpRegistrado(ventaId: v.ventaId, fecha: v.fecha, montoCentavos: v.montoCentavos)],
  );
  final sinVenta = {for (final c in conciliacion.cobrosSinVenta) c.id};
  resultado.addAll([for (final c in porCruzar) if (sinVenta.contains('${c.idServidor}')) _deCobro(c)]);

  // --- contracargos y reclamos: el último aviso de cada uno; si ese ya se vio, no queda nada
  final ultimos = <String, AvisoMp>{};
  for (final a in avisos) {
    if (a.tipo == TipoAvisoMp.cobro) continue;
    final clave = '${a.tipo.name}:${a.mpId}';
    final previo = ultimos[clave];
    if (previo == null || a.idServidor > previo.idServidor) ultimos[clave] = a;
  }
  for (final a in ultimos.values) {
    if (a.visto) continue;
    final porReferencia = a.referencia == null ? null : ventaPorId[ventaDeReferencia[a.referencia]];
    final venta = porReferencia ?? _ventaPorMonto(a, ventas);
    resultado.add(_deProblema(a, venta, exacta: porReferencia != null));
  }

  resultado.sort((x, y) => y.aviso.creado.compareTo(x.aviso.creado));
  return resultado;
}

VentaMp? _ventaPorMonto(AvisoMp a, List<VentaMp> ventas) {
  if (a.montoCentavos == null) return null;
  final referencia = a.fecha ?? a.creado;
  VentaMp? mejor;
  for (final v in ventas) {
    if (v.montoCentavos != a.montoCentavos) continue;
    if (mejor == null || v.fecha.difference(referencia).abs() < mejor.fecha.difference(referencia).abs()) mejor = v;
  }
  return mejor;
}

String _hora(DateTime f) => '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

AvisoParaMostrar _deCobro(AvisoMp c) {
  final cuando = c.fecha ?? c.creado;
  final monto = c.montoCentavos == null ? 'Un cobro' : formatearARS(c.montoCentavos!);
  return AvisoParaMostrar(
    aviso: c,
    titulo: c.montoCentavos == null ? 'Entró un cobro a Mercado Pago' : 'Entraron $monto a Mercado Pago',
    texto: 'A las ${_hora(cuando)} entró un cobro y no hay una venta con ese monto en la app. Revisá si falta cargarla.',
  );
}

AvisoParaMostrar _deProblema(AvisoMp a, VentaMp? venta, {required bool exacta}) {
  final esContracargo = a.tipo == TipoAvisoMp.contracargo;
  final nombre = esContracargo ? 'Contracargo' : 'Reclamo';
  final partes = <String>[];
  if (venta == null) {
    partes.add('No encontré la venta en la app.');
  } else {
    final nro = venta.numero ?? '#${venta.ventaId}';
    partes.add(exacta ? 'Venta $nro (${formatearARS(venta.montoCentavos)}).' : 'Podría ser la venta $nro (${formatearARS(venta.montoCentavos)}).');
  }
  if (esContracargo) {
    partes.add(a.estado == 'documentacion' ? 'Hay que presentar documentación en Mercado Pago.' : 'Mercado Pago lo está resolviendo.');
  } else {
    partes.add(switch (a.estado) {
      'closed' => 'El reclamo está cerrado.',
      'opened' => 'El reclamo está abierto: respondelo en Mercado Pago.',
      _ => 'Mirá el detalle en Mercado Pago.',
    });
  }
  return AvisoParaMostrar(
    aviso: a,
    titulo: a.montoCentavos == null ? nombre : '$nombre de ${formatearARS(a.montoCentavos!)}',
    texto: partes.join(' '),
    ventaId: venta?.ventaId,
    ventaNumero: venta?.numero,
  );
}
