// Imprimir un ticket en la terminal: directo con el access token de este equipo (lo de siempre) o por el servidor de Nodo Sur con la
// cuenta vinculada y el Mercado Pago del negocio. Misma regla que el cobro (`elegirPasarelaPoint`): directo si hay token y terminal
// cargados y no se pidió el servidor; si no, el servidor, que dice qué falta (cuenta, conexión, terminal) en vez de fallar mudo.

import 'dart:math';

import 'package:http/http.dart' as http;

import '../data/impresion_posnet.dart';
import '../domain/ticket.dart';
import 'cuenta_nube.dart';

String _clave() {
  final r = Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// ¿Se imprimiría directo con lo cargado en este equipo?
bool imprimeDirecto({String? accessToken, String? terminalId, bool forzarNube = false}) => !forzarNube && accessToken != null && terminalId != null;

Future<void> imprimirTicketPosnet({
  required Ticket ticket,
  required String encabezadoNegocio,
  String? accessToken,
  String? terminalId,
  String? terminalCobroId,
  bool forzarNube = false,
  AlmacenCuenta? almacen,
  ClienteNube? cliente,
  http.Client? client,
}) async {
  if (imprimeDirecto(accessToken: accessToken, terminalId: terminalId, forzarNube: forzarNube)) {
    return imprimirEnPosnet(
      accessToken: accessToken!,
      terminalId: terminalId!,
      terminalCobroId: terminalCobroId,
      ticket: ticket,
      encabezadoNegocio: encabezadoNegocio,
      client: client,
    );
  }
  final cuenta = await almacen?.leer();
  if (cuenta == null || cliente == null) {
    throw const ImpresionPosnetException(
      'Para imprimir por Nodo Sur vinculá este equipo a tu cuenta y conectá Mercado Pago en horsepos.com/negocio; '
      'o cargá el access token y la terminal en Configuración → Impresión.',
    );
  }
  try {
    await cliente.imprimirTicketPoint(
      cuenta.token,
      externalReference: 'ticket_${DateTime.now().millisecondsSinceEpoch}',
      idempotencyKey: _clave(),
      contenido: contenidoTicketPosnetMp(ticket, encabezadoNegocio: encabezadoNegocio),
    );
  } on ErrorNube catch (e) {
    throw ImpresionPosnetException(e.pideVincularDeNuevo ? 'Este dispositivo ya no está vinculado a la cuenta. Volvé a vincularlo para imprimir.' : e.mensaje);
  }
}
