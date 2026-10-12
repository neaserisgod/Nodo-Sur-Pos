// La conexión de avisos en vivo de la sync (`/api/sync/escuchar`). En la PC y el celular, el WebSocket de dart:io con el token en
// la cabecera. En el navegador no existe dart:io y un WebSocket no puede llevar cabeceras: el token va como subprotocolo
// (`bearer.<token>`), que el sitio acepta solo en esa ruta (`functions/api/sync.js`).
export 'socket_de_avisos_io.dart' if (dart.library.js_interop) 'socket_de_avisos_web.dart';
