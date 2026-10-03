// Estructura de datos pura del comprobante de venta, y su traducción al
// lenguaje de tags de la API de Terminals de MercadoPago (fase 10).

import 'dinero.dart';

/// Una línea del ticket. `cantidad` queda en 1 para pesables (una línea = un
/// lote pesado) y `gramos` es no nulo solo en ese caso.
class LineaTicket {
  final String nombreProducto;
  final int cantidad;
  final int? gramos;
  final int subtotalCentavos;

  const LineaTicket({
    required this.nombreProducto,
    required this.cantidad,
    this.gramos,
    required this.subtotalCentavos,
  });
}

/// Desglose opcional del total. La pantalla de venta solo lo muestra cuando
/// corresponde (layout de venta, columna derecha): sin recargo ni redondeo,
/// no hay nada que desglosar.
class DesgloseTicket {
  final int recargoCigarrillosCentavos;
  final int descuentoCentavos;
  final int redondeoCentavos;

  const DesgloseTicket({
    this.recargoCigarrillosCentavos = 0,
    this.descuentoCentavos = 0,
    this.redondeoCentavos = 0,
  });

  bool get tieneAlgoQueMostrar =>
      recargoCigarrillosCentavos > 0 ||
      descuentoCentavos > 0 ||
      redondeoCentavos > 0;
}

class Ticket {
  /// Número de venta que se imprime (`prefijo-correlativo`); null en un ticket de ejemplo.
  final String? numero;
  final DateTime fecha;
  final String vendedor;
  final List<LineaTicket> lineas;
  final DesgloseTicket desglose;
  final int totalCentavos;

  const Ticket({
    this.numero,
    required this.fecha,
    required this.vendedor,
    required this.lineas,
    required this.desglose,
    required this.totalCentavos,
  });
}

/// Arma el ticket calculando el total a partir de sus propias líneas y
/// desglose, en vez de recibirlo como un valor aparte: es la misma lección
/// del sistema anterior de "una sola fórmula de totales" (Regla 3 de
/// convenciones) aplicada al comprobante — así el total impreso no se puede
/// desalinear de lo que suman las líneas.
Ticket construirTicket({
  String? numero,
  required DateTime fecha,
  required String vendedor,
  required List<LineaTicket> lineas,
  required DesgloseTicket desglose,
}) {
  final subtotalLineas = lineas.fold<int>(
    0,
    (acc, l) => acc + l.subtotalCentavos,
  );
  final total =
      subtotalLineas +
      desglose.recargoCigarrillosCentavos -
      desglose.descuentoCentavos +
      desglose.redondeoCentavos;

  return Ticket(
    numero: numero,
    fecha: fecha,
    vendedor: vendedor,
    lineas: lineas,
    desglose: desglose,
    totalCentavos: total,
  );
}

/// Contenido para `POST /terminals/v1/actions` (type "print") de la API de
/// Terminals de MercadoPago, en su lenguaje propio de tags: `{b}` negrita,
/// `{w}` letra grande, `{s}` chica, `{center}`, `{br}` salto de línea.
///
/// Nota IMPORTANTE, verificada a mano contra una terminal Point real (Newland
/// N950), no documentada así por MercadoPago: `{left}` en la práctica alinea
/// el texto a la DERECHA, y el texto sin tag de alineación queda a la
/// izquierda por default. Se usa así a propósito acá abajo (descripción sin
/// tag = izquierda, precio con `{left}` = derecha) para lograr un layout de
/// dos columnas por línea — la API no tiene un tag de tabla.
String contenidoTicketPosnetMp(
  Ticket ticket, {
  required String encabezadoNegocio,
}) {
  final lineasEncabezado = encabezadoNegocio
      .split('\n')
      .map((linea) => '{center}{w}$linea{/w}{/center}{br}')
      .join();

  final lineasItems = ticket.lineas.map((linea) {
    final cantidadTexto = linea.gramos != null
        ? '${linea.gramos}g'
        : 'x${linea.cantidad}';
    return '${linea.nombreProducto} ($cantidadTexto){br}'
        '{left}${formatearARS(linea.subtotalCentavos)}{/left}{br}';
  }).join();

  final lineaRecargo = ticket.desglose.recargoCigarrillosCentavos > 0
      ? 'Recargo cigarrillos{br}{left}${formatearARS(ticket.desglose.recargoCigarrillosCentavos)}{/left}{br}'
      : '';
  final lineaDescuento = ticket.desglose.descuentoCentavos > 0
      ? 'Descuento{br}{left}-${formatearARS(ticket.desglose.descuentoCentavos)}{/left}{br}'
      : '';
  final lineaRedondeo = ticket.desglose.redondeoCentavos > 0
      ? 'Redondeo{br}{left}${formatearARS(ticket.desglose.redondeoCentavos)}{/left}{br}'
      : '';

  return '$lineasEncabezado'
      '{center}{s}${_formatearFechaHora(ticket.fecha)}{/s}{/center}{br}'
      '${ticket.numero == null ? '' : '{center}{s}Venta ${ticket.numero}{/s}{/center}{br}'}'
      '--------------------------------{br}'
      '$lineasItems'
      '$lineaRecargo'
      '$lineaDescuento'
      '$lineaRedondeo'
      '--------------------------------{br}'
      '{left}{b}TOTAL ${formatearARS(ticket.totalCentavos)}{/b}{/left}{br}'
      '{center}Gracias por su compra{/center}{br}';
}

String _formatearFechaHora(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}
