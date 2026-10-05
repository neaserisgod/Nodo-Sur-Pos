// Gemini le pone nombre y un motivo a las promos sugeridas (El dueño, 2026-10-05). La IA NO decide nada de plata: los pares y los
// precios ya vienen calculados (`repositorio_sugerencia_promos.dart`); acá solo redacta. Si no hay clave, no hay cupo o no hay
// internet, el que llama muestra las sugerencias con el nombre simple ("Yerba + Galletitas") y se sigue igual.
//
// Privacidad (plan gratis de Google): al prompt van solo nombres de productos y números agregados. Nunca clientes ni fiados.

import '../data/repositorio_sugerencia_promos.dart';
import '../domain/dinero.dart';
import 'gemini.dart';

class TextoDePromo {
  const TextoDePromo({required this.nombre, required this.motivo});
  final String nombre;
  final String motivo;
}

const maximoLargoNombreDePromo = 40;

const _instrucciones =
    'Sos el asistente de un almacén de barrio en Bariloche. Te paso combos de productos que los clientes ya se llevan juntos. '
    'Para cada uno escribí: un nombre corto y atractivo para la promo (máximo $maximoLargoNombreDePromo caracteres, sin emojis, '
    'sin comillas) y un motivo de una sola frase para el dueño, en español rioplatense. '
    'Usá solo los datos que te doy; no inventes números ni descuentos. '
    'Respondé únicamente JSON con esta forma: {"promos":[{"i":0,"nombre":"...","motivo":"..."}]}, una entrada por combo.';

/// El pedido: un combo por línea, solo nombres y números.
String armarPedidoDePromos(List<SugerenciaDePromo> sugerencias) {
  final b = StringBuffer('Combos (últimos 90 días de ventas):\n');
  for (var i = 0; i < sugerencias.length; i++) {
    final s = sugerencias[i];
    final articulos = s.componentes
        .map(
          (c) => c.cantidad > 1
              ? '${c.cantidad} x ${c.producto.nombre}'
              : c.producto.nombre,
        )
        .join(' + ');
    b.writeln(
      '$i) $articulos — se llevaron juntos en ${s.par.ventasJuntos} ventas; '
      'sueltos ${formatearARS(s.calculo.listaCentavos)}, la promo costaría ${formatearARS(s.calculo.precioCentavos)} '
      '(el cliente ahorra ${formatearARS(s.ahorroCentavos)}).',
    );
  }
  return b.toString();
}

/// Lo que contestó la IA, por posición. Una entrada rota o ausente queda en null (la sugerencia usa su nombre simple): la
/// respuesta de una IA nunca se da por buena sin mirarla.
List<TextoDePromo?> leerTextosDePromos(Object? json, int cantidad) {
  final resultado = List<TextoDePromo?>.filled(cantidad, null);
  final lista = json is Map ? json['promos'] : null;
  if (lista is! List) return resultado;
  for (final e in lista) {
    if (e is! Map) continue;
    final i = e['i'];
    final nombre = e['nombre'];
    final motivo = e['motivo'];
    if (i is! int ||
        i < 0 ||
        i >= cantidad ||
        nombre is! String ||
        motivo is! String) {
      continue;
    }
    final n = nombre.trim();
    if (n.isEmpty) continue;
    resultado[i] = TextoDePromo(
      nombre: n.length > maximoLargoNombreDePromo
          ? n.substring(0, maximoLargoNombreDePromo).trimRight()
          : n,
      motivo: motivo.trim(),
    );
  }
  return resultado;
}

/// Pide a Gemini los nombres. Lanza [ErrorGemini] si falla; el que llama decide qué mostrar en su lugar.
Future<List<TextoDePromo?>> redactarPromos(
  ClienteGemini cliente,
  List<SugerenciaDePromo> sugerencias,
) async {
  if (sugerencias.isEmpty) return const [];
  final json = await cliente.generarJson(
    armarPedidoDePromos(sugerencias),
    sistema: _instrucciones,
  );
  return leerTextosDePromos(json, sugerencias.length);
}
