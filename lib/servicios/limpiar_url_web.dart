import 'package:web/web.dart' as web;

/// Deja la dirección en la ruta de la app, sin la consulta (y sin dejar el código en el historial).
void limpiarDireccion() => web.window.history.replaceState(null, '', web.window.location.pathname);
