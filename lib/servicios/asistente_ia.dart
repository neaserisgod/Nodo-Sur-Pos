// El pedido a Gemini del asistente de Nodo Sur Servicios (`domain/asistente_ia.dart`). Acá solo se manda y se recibe: qué datos
// van, cómo se valida la respuesta y qué se puede hacer con ella vive en el dominio.

import '../domain/asistente_ia.dart';
import 'gemini.dart';

/// Pregunta a la IA. Lanza [ErrorGemini] si falla (sin clave, sin internet, sin cupo); la pantalla muestra el motivo.
Future<RespuestaIa> preguntarAlAsistente(
  ClienteGemini cliente,
  String pregunta,
  DatosIa datos, {
  List<({String pregunta, String respuesta})> antes = const [],
}) async {
  // Temperatura baja: tiene que leer datos y armar acciones exactas, no redactar.
  final json = await cliente.generarJson(armarPedidoIa(pregunta, datos, antes: antes), sistema: instruccionesAsistenteIa, temperatura: 0.2);
  return leerRespuestaIa(json, datos);
}
