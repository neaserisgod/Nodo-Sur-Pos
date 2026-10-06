// Pedido por WhatsApp a un proveedor (rediseño v4, etapa 8.2): deja el número en la forma que pide `wa.me` y arma el
// mensaje con lo que hay que pedir. Función pura: abrir el link es cosa de la capa de arriba.

/// Deja un número de teléfono como lo espera `wa.me`: solo dígitos, con código de país. Pensado para números argentinos
/// escritos de cualquier forma (con 0 de la característica, con 15, con +54 sin el 9). Un número de otro país se deja
/// como está. Null si no parece un teléfono.
String? normalizarWhatsapp(String texto) {
  var d = texto.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length < 8 || d.length > 15) return null;

  if (d.startsWith('54')) {
    // 54 + 10 dígitos sin el 9 del celular: lo agrega, WhatsApp lo necesita.
    if (d.length == 12) return '549${d.substring(2)}';
    return d;
  }
  if (d.startsWith('0')) {
    d = d.substring(1);
    // 0 + característica (2 a 4 dígitos) + 15 + abonado: el 15 sobra.
    for (final largo in const [2, 3, 4]) {
      if (d.length == 12 && d.substring(largo, largo + 2) == '15') {
        d = d.substring(0, largo) + d.substring(largo + 2);
        break;
      }
    }
    return d.length == 10 ? '549$d' : null;
  }
  if (d.length == 10) return '549$d';
  if (d.length == 11 && d.startsWith('9')) return '54$d';
  // Otro país (o algo que no sabemos corregir): tal cual, WhatsApp dirá si no existe.
  return d.length >= 10 ? d : null;
}

/// Link que abre el chat con el mensaje ya escrito (el que lo manda es quien aprieta "enviar" en WhatsApp).
Uri urlWhatsapp(String numeroNormalizado, String mensaje) =>
    Uri.https('wa.me', '/$numeroNormalizado', {'text': mensaje});

/// Un producto a pedir. [stock] en unidades, o en gramos si [esPesable].
class LineaDePedido {
  const LineaDePedido({required this.nombre, required this.stock, this.esPesable = false});

  final String nombre;
  final int stock;
  final bool esPesable;
}

String _kilos(int gramos) {
  final kilos = gramos / 1000;
  final texto = kilos == kilos.roundToDouble() ? kilos.toStringAsFixed(0) : kilos.toString();
  return texto.replaceAll('.', ',');
}

/// El texto del pedido: cada producto con lo que queda, sin cantidades inventadas — cuánto pedir lo escribe el dueño
/// antes de mandarlo.
String armarMensajePedido({required String proveedor, String? comercio, required List<LineaDePedido> lineas}) {
  final saludo = (comercio == null || comercio.trim().isEmpty)
      ? 'Hola $proveedor.'
      : 'Hola $proveedor, te escribe ${comercio.trim()}.';
  final filas = [
    for (final l in lineas)
      '- ${l.nombre} (${l.stock <= 0 ? 'no queda' : 'quedan ${l.esPesable ? '${_kilos(l.stock)} kg' : l.stock}'})',
  ];
  return '$saludo Necesito pedir:\n${filas.join('\n')}\nGracias.';
}
