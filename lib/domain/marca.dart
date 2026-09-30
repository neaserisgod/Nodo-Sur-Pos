// Cómo se llama lo que se ve: el producto y el comercio.
//
// El producto se llama igual en todos los comercios ([nombreProducto], un solo
// lugar). Cada comercio carga el suyo (nombre y encabezado del ticket) en la
// configuración; mientras no lo haya cargado se muestra el del producto en vez
// de un nombre ajeno o un espacio en blanco.

/// Nombre del producto. Se cambia acá y en ningún otro lado.
const String nombreProducto = 'Nodo Sur POS';

class MarcaNegocio {
  const MarcaNegocio({this.nombreComercio = '', this.encabezadoTicket = ''});

  /// Lo que el comercio cargó, tal cual (puede venir vacío).
  final String nombreComercio;
  final String encabezadoTicket;

  /// ¿El comercio ya cargó su nombre?
  bool get configurada => nombreComercio.trim().isNotEmpty;

  /// Lo que se muestra como nombre (ventana, menú, celular): el del comercio,
  /// o el del producto si todavía no lo cargó.
  String get nombre => configurada ? nombreComercio.trim() : nombreProducto;

  /// Encabezado del ticket, una línea por renglón: el que el comercio armó; si
  /// no hay, su nombre; si tampoco, el del producto.
  String get encabezadoTicketEfectivo => encabezadoTicket.trim().isNotEmpty ? encabezadoTicket.trim() : nombre;

  @override
  bool operator ==(Object other) =>
      other is MarcaNegocio && other.nombreComercio == nombreComercio && other.encabezadoTicket == encabezadoTicket;

  @override
  int get hashCode => Object.hash(nombreComercio, encabezadoTicket);
}
