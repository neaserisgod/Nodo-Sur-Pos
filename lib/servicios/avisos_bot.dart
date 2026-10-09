// Avisos en vivo del bot de WhatsApp (`docs/PLAN-BOT.md`). Cuando el bot manda un pedido, el sitio despierta a los equipos de la
// sucursal por la misma conexión de la sync (`ClienteNube.escuchar`) con `{"bot":{"pedido":N}}`. El aviso solo despierta: la
// pantalla de Encargues vuelve a pedir la lista al sitio.

import 'dart:async';

final StreamController<int> _pedidos = StreamController<int>.broadcast();

/// Ids (del sitio) de los pedidos nuevos que mandó el bot.
Stream<int> get avisosPedidoBot => _pedidos.stream;

/// Lo llama la conexión en vivo de la sync al recibir un pedido nuevo del bot.
void avisarPedidoBot(int id) => _pedidos.add(id);
