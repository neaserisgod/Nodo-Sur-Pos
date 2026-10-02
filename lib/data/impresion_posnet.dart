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

/// Mercado Pago pasó a exigir `MODELO__SERIAL` también para imprimir (antes aceptaba el serial pelado: ver TRAMPAS.md). Si el
/// campo de impresión quedó con el serial solo y el de cobro es LA MISMA terminal en formato completo, se usa ese: no hace
/// falta que quien configura cargue el mismo dato dos veces para que el ticket salga.
String terminalParaImprimir(String terminalId, String? terminalCobroId) {
  if (terminalId.contains('__')) return terminalId;
  final cobro = terminalCobroId;
  return cobro != null && cobro.endsWith('__$terminalId') ? cobro : terminalId;
}

/// Lo que Mercado Pago contestó, legible: `errors[{code, message, details}]` o `message`; si no, el cuerpo tal cual.
String _detalleError(String cuerpo) {
  try {
    final j = jsonDecode(cuerpo);
    if (j is Map) {
      final errores = j['errors'];
      if (errores is List && errores.isNotEmpty && errores.first is Map) {
        final e = errores.first as Map;
        final detalles = e['details'] is List ? (e['details'] as List).join('; ') : null;
        return [e['code'], e['message'], detalles].where((x) => x != null && x.toString().isNotEmpty).join(' · ');
      }
      if (j['message'] != null) return j['message'].toString();
    }
  } catch (_) {
    // Cuerpo no-JSON: se usa tal cual.
  }
  return cuerpo;
}

Future<void> imprimirEnPosnet({
  required String accessToken,
  required String terminalId,
  String? terminalCobroId,
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
          'point': {'terminal_id': terminalParaImprimir(terminalId, terminalCobroId), 'subtype': 'custom'},
        },
        'content': contenido,
      }),
    );

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      final mensaje = _detalleError(respuesta.body);
      throw ImpresionPosnetException('MercadoPago Terminals API (${respuesta.statusCode}): $mensaje');
    }
  } finally {
    if (client == null) cliente.close();
  }
}
