// Evita mandar una request HTTP por cada tecla escrita en un buscador de la
// companion — a diferencia del campo único del escritorio (que filtra un
// catálogo ya en memoria), cada letra acá dispara una consulta real por
// WiFi contra el servidor embebido de la PC. Sin esto, escribir "coca"
// manda 4 requests casi simultáneas — además de ser caro, no hay garantía
// de que lleguen en orden (jitter de WiFi real), así que la respuesta de
// "c" puede llegar después que la de "coca" y pisar el resultado correcto
// con uno viejo. Los cuatro buscadores de la companion (`pantalla_menu_
// companion.dart`, `pantalla_precios.dart`, `pantalla_consultar_precio.dart`,
// `pantalla_carga_historica.dart`) usan esto junto con un chequeo de "¿el
// texto todavía es el que pedí?" antes de aplicar la respuesta.
import 'dart:async';

class Debouncer {
  Debouncer({this.duracion = const Duration(milliseconds: 300)});

  final Duration duracion;
  Timer? _timer;

  void ejecutar(void Function() accion) {
    _timer?.cancel();
    _timer = Timer(duracion, accion);
  }

  /// Para el caso "se borró el campo": no tiene sentido esperar
  /// [duracion] para mostrar que no hay nada que buscar.
  void cancelar() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}
