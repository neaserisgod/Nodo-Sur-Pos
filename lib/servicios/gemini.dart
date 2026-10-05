// Cliente de la IA de Google (Gemini) con la clave gratuita del plan personal (El dueño, 2026-10-05: "integrar la IA de
// Google gratuita del plan personal por API key").
//
// La clave es de ESTE equipo: vive en las preferencias locales, igual que "Cobrar e imprimir por Nodo Sur" — no en
// `configuracion_negocio_tabla`, porque esa tabla se sincroniza a la nube y al celular, y una clave personal no puede
// viajar con ella. Tampoco entra en las copias de la base.
//
// Privacidad del plan gratis: Google puede usar lo que se manda para mejorar sus productos. Por eso quien arme un prompt
// manda productos, precios y totales agregados — nunca nombres de clientes ni de fiados. Eso se decide en cada uso, no acá.
//
// Nada de esto toca dinero ni caja: es consulta de apoyo, y si falla (sin clave, sin cupo, sin internet) la app sigue igual.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Un modelo con cupo gratis. Si Google lo retira, "Probar" en Configuración avisa que ya no existe y se cambia acá.
const modeloGeminiPorDefecto = 'gemini-2.5-flash';

const _claveGuardada = 'gemini_api_key';
const _base = 'https://generativelanguage.googleapis.com/v1beta';

/// La clave de API de este equipo. Se lee una vez al arrancar ([cargar]) y después va en memoria.
abstract final class ClaveGemini {
  static String? _valor;

  static String? get valor => _valor;
  static bool get configurada => _valor != null;

  static Future<void> cargar() async {
    try {
      _valor = _limpia((await SharedPreferences.getInstance()).getString(_claveGuardada));
    } catch (_) {
      _valor = null;
    }
  }

  /// Guarda [clave]; vacía o solo espacios la borra.
  static Future<void> guardar(String? clave) async {
    _valor = _limpia(clave);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_valor == null) {
        await prefs.remove(_claveGuardada);
      } else {
        await prefs.setString(_claveGuardada, _valor!);
      }
    } catch (_) {
      // Sin almacenamiento vale hasta cerrar la app.
    }
  }

  static String? _limpia(String? clave) {
    final t = clave?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// Solo para tests.
  static void fijarParaTest(String? clave) => _valor = _limpia(clave);
}

/// Un fallo de la consulta, con un mensaje que se le puede mostrar tal cual al dueño. Nunca lleva la clave.
class ErrorGemini implements Exception {
  const ErrorGemini(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

class ClienteGemini {
  ClienteGemini({
    required this.apiKey,
    this.modelo = modeloGeminiPorDefecto,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  /// Con la clave guardada en este equipo; [ErrorGemini] si no hay ninguna.
  factory ClienteGemini.guardado({String modelo = modeloGeminiPorDefecto, http.Client? client}) {
    final clave = ClaveGemini.valor;
    if (clave == null) throw const ErrorGemini('Falta cargar la clave de la IA en Configuración › Asistente IA.');
    return ClienteGemini(apiKey: clave, modelo: modelo, client: client);
  }

  final String apiKey;
  final String modelo;
  final Duration timeout;
  final http.Client _client;

  /// Manda [prompt] y devuelve el texto de la respuesta. [sistema] son las instrucciones fijas (rol, formato).
  /// Con [json] el modelo contesta JSON válido — usar [generarJson] para recibirlo ya decodificado.
  Future<String> generarTexto(String prompt, {String? sistema, double temperatura = 0.7, bool json = false}) async {
    final cuerpo = <String, Object?>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      if (sistema != null)
        'systemInstruction': {
          'parts': [
            {'text': sistema},
          ],
        },
      'generationConfig': {
        'temperature': temperatura,
        if (json) 'responseMimeType': 'application/json',
      },
    };

    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('$_base/models/$modelo:generateContent'),
            // La clave va en el encabezado, no en la URL: una URL puede quedar en registros.
            headers: {'x-goog-api-key': apiKey, 'content-type': 'application/json'},
            body: jsonEncode(cuerpo),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ErrorGemini('La IA tardó demasiado en contestar. Probá de nuevo.');
    } on SocketException {
      throw const ErrorGemini('No hay conexión a internet.');
    } on http.ClientException {
      throw const ErrorGemini('No hay conexión a internet.');
    }

    if (r.statusCode != 200) throw ErrorGemini(_mensajeDeError(r.statusCode, r.body, modelo));
    return _textoDeRespuesta(r.body);
  }

  /// Como [generarTexto] pero pidiendo y decodificando JSON. [ErrorGemini] si lo que vuelve no es JSON.
  Future<Object?> generarJson(String prompt, {String? sistema, double temperatura = 0.4}) async {
    final texto = await generarTexto(prompt, sistema: sistema, temperatura: temperatura, json: true);
    try {
      return jsonDecode(texto);
    } on FormatException {
      throw const ErrorGemini('La IA contestó algo que no se pudo leer. Probá de nuevo.');
    }
  }

  /// Una consulta mínima: confirma que la clave y el modelo andan. Devuelve null si anda, o el motivo si no.
  Future<String?> probar() async {
    try {
      await generarTexto('Respondé solo con la palabra: ok', temperatura: 0);
      return null;
    } on ErrorGemini catch (e) {
      return e.mensaje;
    }
  }

  void close() => _client.close();
}

/// Lo que hacen "Guardar" en Configuración de la PC y del celular (una sola forma de cargar la clave en las dos apps):
/// prueba [clave] contra Google y, si anda, la guarda. Devuelve null si quedó guardada, o el motivo si no — y entonces NO se
/// guarda, para no dejar una clave rota. Una clave vacía borra la que había.
Future<String?> probarYGuardarClave(String clave, {http.Client? client}) async {
  if (clave.trim().isEmpty) {
    await ClaveGemini.guardar(null);
    return null;
  }
  final cliente = ClienteGemini(apiKey: clave.trim(), client: client);
  try {
    final motivo = await cliente.probar();
    if (motivo != null) return motivo;
    await ClaveGemini.guardar(clave);
    return null;
  } finally {
    cliente.close();
  }
}

String _textoDeRespuesta(String cuerpo) {
  final Object? data;
  try {
    data = jsonDecode(cuerpo);
  } on FormatException {
    throw const ErrorGemini('La IA contestó algo que no se pudo leer. Probá de nuevo.');
  }
  final candidatos = data is Map ? data['candidates'] : null;
  if (candidatos is List && candidatos.isNotEmpty && candidatos.first is Map) {
    final contenido = (candidatos.first as Map)['content'];
    final partes = contenido is Map ? contenido['parts'] : null;
    if (partes is List) {
      final texto = [
        for (final p in partes)
          if (p is Map && p['text'] is String) p['text'] as String,
      ].join();
      if (texto.isNotEmpty) return texto;
    }
  }
  // Sin texto: Google cortó la respuesta (filtros de seguridad, etc.).
  final bloqueo = data is Map && data['promptFeedback'] is Map ? (data['promptFeedback'] as Map)['blockReason'] : null;
  throw ErrorGemini(bloqueo == null ? 'La IA no devolvió respuesta.' : 'La IA no quiso contestar ($bloqueo).');
}

String _mensajeDeError(int estado, String cuerpo, String modelo) {
  switch (estado) {
    case 400:
      // Google contesta 400 (no 401) cuando la clave está mal escrita.
      if (cuerpo.contains('API key not valid') || cuerpo.contains('API_KEY_INVALID')) {
        return 'La clave no es válida. Revisá que esté copiada completa.';
      }
      return 'La consulta no se pudo procesar${_detalle(cuerpo)}';
    case 401:
    case 403:
      return 'La clave no tiene permiso para usar la IA${_detalle(cuerpo)}';
    case 404:
      return 'El modelo "$modelo" ya no está disponible.';
    case 429:
      return 'Se acabó el cupo gratis por ahora (hay un límite por minuto y otro por día). Probá en un rato.';
    default:
      if (estado >= 500) return 'Los servidores de Google no responden ahora. Probá en un rato.';
      return 'La IA devolvió un error ($estado)${_detalle(cuerpo)}';
  }
}

/// El texto que manda Google en `error.message`, para no perder el motivo real. Nunca contiene la clave.
String _detalle(String cuerpo) {
  try {
    final data = jsonDecode(cuerpo);
    final mensaje = data is Map && data['error'] is Map ? (data['error'] as Map)['message'] : null;
    if (mensaje is String && mensaje.isNotEmpty) return ': $mensaje';
  } on FormatException {
    // Cuerpo que no es JSON: sin detalle.
  }
  return '.';
}
