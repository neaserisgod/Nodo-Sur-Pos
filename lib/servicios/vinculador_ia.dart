// Ayuda de la IA para vincular las líneas de una factura que el parecido de nombre no resolvió (El dueño, 2026-10-05). Le toca elegir
// ENTRE los productos que se le pasan (los del proveedor y las alternativas más parecidas), nunca inventar uno: lo que devuelve se
// valida contra esa lista y queda como "para confirmar". Sin clave, sin cupo o sin internet, el que llama sigue con lo que ya tenía.
//
// Privacidad (plan gratis de Google): van descripciones de la factura y nombres de productos. Nunca precios, costos ni datos del comprador.

import '../domain/vinculo_factura.dart';
import 'gemini.dart';

const _instrucciones = '''
Sos el asistente de un almacén de barrio en Argentina. Te paso líneas de una factura de un proveedor y la lista de productos del comercio. Las descripciones de la factura vienen abreviadas (por ejemplo ALF = alfajor, BL = blanco, CLAS = clásico, GALL = galletitas, "(12)" es el tamaño del pack del proveedor).
Para cada línea elegí el producto de la lista que es EXACTAMENTE el mismo artículo: misma marca, misma variante y mismo tamaño. Si ninguno lo es, o dudás entre dos, devolvé null en "producto_id". Solo podés elegir ids de la lista: no inventes productos ni ids.
Respondé únicamente JSON con esta forma: {"vinculos":[{"i":0,"producto_id":123,"motivo":"..."}]}, una entrada por cada línea.
''';

/// Cuántos productos se le pasan como máximo a la IA (un pedido enorme no mejora la respuesta y gasta cupo).
const maximoCandidatosParaIa = 300;

/// Los productos que se le muestran a la IA: los del proveedor de la factura y las alternativas que el parecido de nombre ofreció.
List<ProductoCandidato> candidatosParaIa(List<ProductoCandidato> catalogo, int? proveedorId, List<PropuestaDeVinculo> propuestas) {
  final alternativas = {for (final p in propuestas) ...p.alternativas};
  final elegidos = [
    for (final c in catalogo)
      if ((proveedorId != null && c.proveedorId == proveedorId) || alternativas.contains(c.id)) c,
  ];
  return elegidos.take(maximoCandidatosParaIa).toList();
}

/// El pedido: las líneas a vincular (con su posición) y la lista de productos con su id.
String armarPedidoDeVinculos(List<({int posicion, LineaAVincular linea})> lineas, List<ProductoCandidato> candidatos) {
  final b = StringBuffer('Líneas de la factura:\n');
  for (final l in lineas) {
    final codigo = l.linea.codigo == null ? '' : '[${l.linea.codigo}] ';
    b.writeln('${l.posicion}) $codigo${l.linea.descripcion}');
  }
  b.writeln('\nProductos del comercio (id: nombre):');
  for (final c in candidatos) {
    b.writeln('${c.id}: ${c.nombre}');
  }
  return b.toString();
}

/// Lo que contestó la IA: posición de la línea → id de producto. Se descartan las posiciones que no se pidieron y los ids que no estaban
/// en la lista; una respuesta rota no tira.
Map<int, int> leerVinculosDeIa(Object? json, {required Set<int> posicionesPedidas, required Set<int> idsPresentados}) {
  final lista = json is Map ? json['vinculos'] : null;
  final resultado = <int, int>{};
  if (lista is! List) return resultado;
  for (final e in lista) {
    if (e is! Map) continue;
    final i = e['i'];
    final id = e['producto_id'];
    if (i is int && id is int && posicionesPedidas.contains(i) && idsPresentados.contains(id)) resultado[i] = id;
  }
  return resultado;
}

/// Le pide a Gemini que vincule [pendientes] eligiendo entre [candidatos]. Lanza [ErrorGemini] si falla; el que llama decide qué hacer.
Future<Map<int, int>> vincularConIa(
  ClienteGemini cliente, {
  required List<({int posicion, LineaAVincular linea})> pendientes,
  required List<ProductoCandidato> candidatos,
}) async {
  if (pendientes.isEmpty || candidatos.isEmpty) return const {};
  final json = await cliente.generarJson(armarPedidoDeVinculos(pendientes, candidatos), sistema: _instrucciones, temperatura: 0);
  return leerVinculosDeIa(
    json,
    posicionesPedidas: {for (final p in pendientes) p.posicion},
    idsPresentados: {for (final c in candidatos) c.id},
  );
}
