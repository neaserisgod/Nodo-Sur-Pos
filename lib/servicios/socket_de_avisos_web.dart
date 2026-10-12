import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// El subprotocolo que identifica a la app; el token va en otro (`bearer.<token>`) y el sitio contesta con este.
const protocoloAvisos = 'nodosur';

Future<Stream<dynamic>> abrirSocketDeAvisos(Uri uri, Map<String, String> cabeceras) async {
  final token = (cabeceras['Authorization'] ?? '').replaceFirst('Bearer ', '');
  final socket = web.WebSocket(uri.toString(), [protocoloAvisos.toJS, 'bearer.$token'.toJS].toJS);
  final abierto = Completer<void>();
  final mensajes = StreamController<dynamic>(onCancel: () => socket.close());
  socket.onopen = ((web.Event _) => abierto.isCompleted ? null : abierto.complete()).toJS;
  socket.onmessage = ((web.MessageEvent e) {
    final dato = e.data;
    mensajes.add(dato.isA<JSString>() ? (dato as JSString).toDart : null);
  }).toJS;
  socket.onerror = ((web.Event _) {
    if (!abierto.isCompleted) abierto.completeError(StateError('No se pudo abrir el aviso en vivo'));
  }).toJS;
  socket.onclose = ((web.CloseEvent _) {
    if (!abierto.isCompleted) abierto.completeError(StateError('Se cerró el aviso en vivo'));
    mensajes.close();
  }).toJS;
  await abierto.future.timeout(const Duration(seconds: 20), onTimeout: () {
    socket.close();
    throw TimeoutException('aviso en vivo');
  });
  return mensajes.stream;
}
