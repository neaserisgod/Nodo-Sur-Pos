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
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Los modelos con cupo gratis, del que más conviene al que menos. Google pide usar los 3.x en proyectos nuevos y dejó los 2.5
/// solo para cuentas que ya los usaban: con una clave nueva, `gemini-2.5-flash` contesta 404 (pasó el 2026-10-05). Por eso
/// "Guardar y probar" recorre esta lista y se queda con el primero que le anda a la clave; sumar uno nuevo es agregarlo acá.
const modelosGemini = [
  'gemini-3.5-flash-lite',
  'gemini-3.8-flash',
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
  'gemini-2.5-flash-lite',
  'gemini-2.5-flash',
];

/// El que se usa mientras no se haya probado ninguno con la clave.
const modeloGeminiPorDefecto = 'gemini-3.5-flash-lite';

const _claveGuardada = 'gemini_api_key';
const _modeloGuardado = 'gemini_modelo';
const _base = 'https://generativelanguage.googleapis.com/v1beta';

/// La clave de API de este equipo, y el modelo con el que se probó. Se leen una vez al arrancar ([cargar]) y después van en memoria.
abstract final class ClaveGemini {
  static String? _valor;
  static String? _modelo;

  static String? get valor => _valor;
  static bool get configurada => _valor != null;

  /// El modelo que le anduvo a esta clave al probarla; null si todavía no se probó ninguno.
  static String? get modelo => _modelo;

  static Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _valor = _limpia(prefs.getString(_claveGuardada));
      _modelo = _valor == null ? null : _limpia(prefs.getString(_modeloGuardado));
    } catch (_) {
      _valor = null;
      _modelo = null;
    }
  }

  /// Guarda [clave] y el [modelo] que anduvo con ella; una clave vacía o solo espacios borra las dos cosas.
  static Future<void> guardar(String? clave, {String? modelo}) async {
    _valor = _limpia(clave);
    _modelo = _valor == null ? null : _limpia(modelo);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_valor == null) {
        await prefs.remove(_claveGuardada);
        await prefs.remove(_modeloGuardado);
      } else {
        await prefs.setString(_claveGuardada, _valor!);
        if (_modelo == null) {
          await prefs.remove(_modeloGuardado);
        } else {
          await prefs.setString(_modeloGuardado, _modelo!);
        }
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
  static void fijarParaTest(String? clave, {String? modelo}) {
    _valor = _limpia(clave);
    _modelo = _limpia(modelo);
  }
}

/// Un archivo para que Gemini lo mire junto con el pedido: una foto (`image/jpeg`, `image/png`...) o un `application/pdf`.
class AdjuntoGemini {
  const AdjuntoGemini(this.mimeType, this.bytes);
  final String mimeType;
  final Uint8List bytes;
}

/// Lo que Google acepta en un solo pedido, entre texto y archivos (20 MB). Con margen: el base64 pesa un tercio más.
const maximoBytesAdjuntosGemini = 14 * 1024 * 1024;

/// Un fallo de la consulta, con un mensaje que se le puede mostrar tal cual al dueño. Nunca lleva la clave.
class ErrorGemini implements Exception {
  const ErrorGemini(this.mensaje, {this.estado});
  final String mensaje;

  /// El código HTTP que contestó Google, si fue una respuesta de Google (null si falló antes: sin internet, demora).
  final int? estado;

  @override
  String toString() => mensaje;
}

class ClienteGemini {
  ClienteGemini({
    required this.apiKey,
    this.modelo = modeloGeminiPorDefecto,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client(),
       _propio = client == null;

  /// Con la clave guardada en este equipo y el modelo que le anduvo; [ErrorGemini] si no hay clave.
  factory ClienteGemini.guardado({String? modelo, http.Client? client}) {
    final clave = ClaveGemini.valor;
    if (clave == null) throw const ErrorGemini('Falta cargar la clave de la IA en Configuración › Asistente IA.');
    return ClienteGemini(apiKey: clave, modelo: modelo ?? ClaveGemini.modelo ?? modeloGeminiPorDefecto, client: client);
  }

  final String apiKey;
  final String modelo;
  final Duration timeout;
  final http.Client _client;

  /// Un cliente prestado (el de un test) no se cierra: lo cierra quien lo creó.
  final bool _propio;

  /// Manda [prompt] y devuelve el texto de la respuesta. [sistema] son las instrucciones fijas (rol, formato).
  /// Con [json] el modelo contesta JSON válido — usar [generarJson] para recibirlo ya decodificado.
  Future<String> generarTexto(
    String prompt, {
    String? sistema,
    double temperatura = 0.7,
    bool json = false,
    List<AdjuntoGemini> adjuntos = const [],
  }) async {
    if (adjuntos.fold<int>(0, (a, x) => a + x.bytes.length) > maximoBytesAdjuntosGemini) {
      throw const ErrorGemini('Los archivos pesan demasiado para mandarlos juntos. Probá con menos páginas o fotos más chicas.');
    }
    final cuerpo = <String, Object?>{
      'contents': [
        {
          'role': 'user',
          // El texto va antes que los archivos: así lo recomienda Google.
          'parts': [
            {'text': prompt},
            for (final a in adjuntos)
              {
                'inlineData': {'mimeType': a.mimeType, 'data': base64Encode(a.bytes)},
              },
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

    if (r.statusCode != 200) throw ErrorGemini(_mensajeDeError(r.statusCode, r.body, modelo), estado: r.statusCode);
    return _textoDeRespuesta(r.body);
  }

  /// Como [generarTexto] pero pidiendo y decodificando JSON. [ErrorGemini] si lo que vuelve no es JSON.
  Future<Object?> generarJson(
    String prompt, {
    String? sistema,
    double temperatura = 0.4,
    List<AdjuntoGemini> adjuntos = const [],
  }) async {
    final texto = await generarTexto(prompt, sistema: sistema, temperatura: temperatura, json: true, adjuntos: adjuntos);
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

  void close() {
    if (_propio) _client.close();
  }
}

/// Lo que hacen "Guardar" en Configuración de la PC y del celular (una sola forma de cargar la clave en las dos apps):
/// prueba [clave] contra Google y, si anda, la guarda junto con el modelo que le anduvo. Devuelve null si quedó guardada, o el
/// motivo si no — y entonces NO se guarda, para no dejar una clave rota. Una clave vacía borra la que había.
///
/// Recorre [modelosGemini] y salta al siguiente solo con un 404 (modelo no disponible para esta clave). Cualquier otro fallo
/// (clave mala, sin cupo, sin internet) corta ahí: probar otro modelo no lo arregla.
Future<String?> probarYGuardarClave(String clave, {http.Client? client}) async {
  final limpia = clave.trim();
  if (limpia.isEmpty) {
    await ClaveGemini.guardar(null);
    return null;
  }
  for (final modelo in modelosGemini) {
    final cliente = ClienteGemini(apiKey: limpia, modelo: modelo, client: client);
    try {
      await cliente.generarTexto('Respondé solo con la palabra: ok', temperatura: 0);
      await ClaveGemini.guardar(limpia, modelo: modelo);
      return null;
    } on ErrorGemini catch (e) {
      if (e.estado != 404) return e.mensaje;
    } finally {
      cliente.close();
    }
  }
  return 'Ningún modelo gratuito de Google está disponible con esta clave. Probá con otra clave, o creá una nueva en aistudio.google.com/apikey.';
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
      return 'El modelo "$modelo" no está disponible para tu clave. Tocá "Guardar y probar" en Configuración › Asistente IA para elegir otro.';
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
