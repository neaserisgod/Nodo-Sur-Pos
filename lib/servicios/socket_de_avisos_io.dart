import 'dart:async';
import 'dart:io';

Future<Stream<dynamic>> abrirSocketDeAvisos(Uri uri, Map<String, String> cabeceras) async {
  final socket = await WebSocket.connect(uri.toString(), headers: cabeceras).timeout(const Duration(seconds: 20));
  // Ping del protocolo (no se cobra y lo contesta el borde de Cloudflare): si la red se cae sin avisar, el socket
  // se cierra solo en vez de quedar "conectado" sin recibir nunca nada.
  socket.pingInterval = const Duration(seconds: 45);
  return socket;
}
