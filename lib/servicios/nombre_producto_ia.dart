// "Mejorar nombre con IA" al crear un producto desde una línea de factura (El dueño, 2026-10-07). Solo cuando el dueño lo pide: el nombre
// ya sale armado gratis con las palabras del catálogo (`nombreSugeridoDesdeFactura`), y la IA es para lo que eso no deduce ("MRL" →
// Marlboro, acentos que el catálogo no tiene). Una llamada por producto. Lo que contesta es una propuesta en el campo: el dueño la ve
// y la corrige antes de guardar.
//
// Privacidad (plan gratis de Google): va la descripción de la factura y nombres de productos como ejemplo de estilo. Nunca precios,
// costos ni datos del comprador.

import 'gemini.dart';

const _instrucciones = '''
Sos el asistente de un almacén de barrio en Argentina. Te paso la descripción de un producto tal como viene en la factura del proveedor (abreviada: ALF = alfajor, BL = blanco o blanca, GALL = galletitas, BX = box, "(12)" es el pack del proveedor) y algunos nombres de productos del comercio como ejemplo de estilo.
Armá el nombre con el que el comercio lo cargaría: palabras completas, marca, variante y tamaño, con acentos y mayúscula inicial por palabra, como en los ejemplos. No agregues nada que la descripción no diga y no pongas el pack del proveedor.
Respondé únicamente JSON con esta forma: {"nombre":"..."}
''';

/// Cuántos nombres del catálogo se mandan como ejemplo de estilo (alcanza para copiar el formato sin gastar cupo).
const maximoEjemplosDeNombre = 20;

String armarPedidoDeNombre(String descripcion, List<String> ejemplos) {
  final b = StringBuffer('Descripción en la factura: $descripcion\n');
  if (ejemplos.isNotEmpty) {
    b.writeln('\nEjemplos de nombres del comercio:');
    for (final e in ejemplos.take(maximoEjemplosDeNombre)) {
      b.writeln('- $e');
    }
  }
  return b.toString();
}

/// El nombre que contestó la IA, o null si la respuesta no trae uno usable (vacío o desmedido).
String? leerNombreDeIa(Object? json) {
  final n = json is Map ? json['nombre'] : null;
  if (n is! String) return null;
  final limpio = n.replaceAll(RegExp(r'\s+'), ' ').trim();
  return limpio.isEmpty || limpio.length > 80 ? null : limpio;
}

/// Le pide a Gemini el nombre del producto de [descripcion], con [ejemplos] del catálogo para copiar el estilo. Lanza [ErrorGemini] si
/// falla o si la respuesta no trae un nombre.
Future<String> mejorarNombreConIa(ClienteGemini cliente, {required String descripcion, List<String> ejemplos = const []}) async {
  final json = await cliente.generarJson(armarPedidoDeNombre(descripcion, ejemplos), sistema: _instrucciones, temperatura: 0);
  final nombre = leerNombreDeIa(json);
  if (nombre == null) throw const ErrorGemini('La IA no devolvió un nombre. Probá de nuevo o escribilo a mano.');
  return nombre;
}
