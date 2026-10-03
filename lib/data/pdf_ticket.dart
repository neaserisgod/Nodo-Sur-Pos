// PDF local del ticket (fase 10, prioridad 3) — se guarda SIEMPRE, sin
// importar si además se manda a imprimir al posnet: es la fuente real para
// "reimprimir después" (nombre con fecha y número de venta).

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/dinero.dart';
import '../domain/ticket.dart';
import 'repositorio_ticket.dart';
import 'database.dart';

const double _anchoTicket = 220;

String nombreArchivoTicket({required int ventaId, String? numero, required DateTime fecha}) {
  String dos(int n) => n.toString().padLeft(2, '0');
  // Las ventas anteriores al número global llegan como "#id": ahí se sigue nombrando por el id local.
  final nombre = numero != null && !numero.startsWith('#') ? numero : ventaId.toString().padLeft(5, '0');
  return '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}_venta-$nombre.pdf';
}

String _formatearFechaHora(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}

pw.Widget _filaMonto(String etiqueta, int centavos, {bool negrita = false}) {
  final estilo = pw.TextStyle(
    fontSize: negrita ? 10 : 9,
    fontWeight: negrita ? pw.FontWeight.bold : null,
  );
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(etiqueta, style: estilo),
      pw.Text(formatearARS(centavos), style: estilo),
    ],
  );
}

/// Layout angosto tipo recibo (no A4): el mismo contenido que se manda al
/// posnet (`contenidoTicketPosnetMp`), pero como PDF de archivo.
Future<Uint8List> generarPdfTicket(
  Ticket ticket, {
  required String encabezadoNegocio,
}) async {
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(_anchoTicket, double.infinity, marginAll: 10),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final linea in encabezadoNegocio.split('\n'))
              pw.Center(
                child: pw.Text(
                  linea,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            pw.Center(
              child: pw.Text(
                _formatearFechaHora(ticket.fecha),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            if (ticket.numero != null)
              pw.Center(child: pw.Text('Venta ${ticket.numero}', style: const pw.TextStyle(fontSize: 8))),
            pw.SizedBox(height: 4),
            pw.Divider(),
            for (final linea in ticket.lineas)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1),
                child: _filaMonto(
                  '${linea.nombreProducto} (${linea.gramos != null ? '${linea.gramos}g' : 'x${linea.cantidad}'})',
                  linea.subtotalCentavos,
                ),
              ),
            if (ticket.desglose.recargoCigarrillosCentavos > 0)
              _filaMonto(
                'Recargo cigarrillos',
                ticket.desglose.recargoCigarrillosCentavos,
              ),
            if (ticket.desglose.descuentoCentavos > 0)
              _filaMonto('Descuento', -ticket.desglose.descuentoCentavos),
            if (ticket.desglose.redondeoCentavos > 0)
              _filaMonto('Redondeo', ticket.desglose.redondeoCentavos),
            pw.Divider(),
            _filaMonto('TOTAL', ticket.totalCentavos, negrita: true),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'Gracias por su compra',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

Future<String> guardarTicketPdf(
  AppDatabase db, {
  required int ventaId,
  required String carpetaDestino,
  required String encabezadoNegocio,
}) async {
  final ticket = await ticketDeVenta(db, ventaId);
  final bytes = await generarPdfTicket(
    ticket,
    encabezadoNegocio: encabezadoNegocio,
  );

  await Directory(carpetaDestino).create(recursive: true);
  final ruta = p.join(
    carpetaDestino,
    nombreArchivoTicket(ventaId: ventaId, numero: ticket.numero, fecha: ticket.fecha),
  );
  await File(ruta).writeAsBytes(bytes);
  return ruta;
}
