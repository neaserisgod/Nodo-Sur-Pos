// Avisos en vivo del bot de WhatsApp (`docs/PLAN-BOT.md`). Cuando el bot manda un pedido, el sitio despierta a los equipos de la
// sucursal por la misma conexión de la sync (`ClienteNube.escuchar`) con `{"bot":{"pedido":N}}`. El aviso solo despierta: la
// pantalla de Encargues vuelve a pedir la lista al sitio.

import 'dart:async';

import 'sonidos.dart';

final StreamController<int> _pedidos = StreamController<int>.broadcast();

/// Ids (del sitio) de los pedidos nuevos que mandó el bot.
Stream<int> get avisosPedidoBot => _pedidos.stream;

/// Lo llama la conexión en vivo de la sync al recibir un pedido nuevo del bot. Suena en todos los equipos de la sucursal (el
/// aviso les llega a todos); el mismo aviso llega también cuando se paga un pedido con el link, y suena igual: pasó algo con un
/// pedido.
void avisarPedidoBot(int id) {
  sonidos.sonar(Sonido.aviso);
  _pedidos.add(id);
}

final StreamController<String> _turnos = StreamController<String>.broadcast();

/// Ids (del sitio) de los turnos que dio o cambió el bot (negocios de servicios): la Agenda los baja en el momento.
Stream<String> get avisosTurnoBot => _turnos.stream;

void avisarTurnoBot(String id) => _turnos.add(id);
