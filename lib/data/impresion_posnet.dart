// Imprime un ticket en la terminal Point de MercadoPago configurada
// (fase 10, prioridad 3) vía POST /terminals/v1/actions (type "print") —
// acción independiente de cuál terminal cobró la venta (Regla de esta fase:
// acá siempre se usa la terminal dedicada a imprimir, nunca la de cobro).
//
// Contrapartida de la excepción "sin red" del stack (CLAUDE.md): esta es la
// única acción de la app que llama a un servidor externo. Un fallo acá nunca
// debe tocar la venta ya cobrada — el llamador decide qué hacer con el
// error, esta función solo garantiza que sea un error claro, no una
// excepción críptica de `http`.

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/ticket.dart';

class ImpresionPosnetException implements Exception {
  final String mensaje;
  const ImpresionPosnetException(this.mensaje);

  @override
  String toString() => mensaje;
}

String _claveIdempotencia() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> imprimirEnPosnet({
  required String accessToken,
  required String terminalId,
  required Ticket ticket,
  required String encabezadoNegocio,
  http.Client? client,
}) async {
  final contenido = contenidoTicketPosnetMp(ticket, encabezadoNegocio: encabezadoNegocio);
  final cliente = client ?? http.Client();

  try {
    final respuesta = await cliente.post(
      Uri.parse('https://api.mercadopago.com/terminals/v1/actions'),
      headers: {
        'Content-Type': 'application/json',
        'X-Idempotency-Key': _claveIdempotencia(),
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'type': 'print',
        'external_reference': 'ticket_${DateTime.now().millisecondsSinceEpoch}',
        'config': {
          'point': {'terminal_id': terminalId, 'subtype': 'custom'},
        },
        'content': contenido,
      }),
    );

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      var mensaje = respuesta.body;
      try {
        final cuerpo = jsonDecode(respuesta.body);
        if (cuerpo is Map && cuerpo['message'] != null) mensaje = cuerpo['message'].toString();
      } catch (_) {
        // Cuerpo no-JSON: se usa tal cual.
      }
      throw ImpresionPosnetException('MercadoPago Terminals API (${respuesta.statusCode}): $mensaje');
    }
  } finally {
    if (client == null) cliente.close();
  }
}
