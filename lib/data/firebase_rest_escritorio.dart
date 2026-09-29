// Cliente REST de Firebase Auth + Firestore, exclusivo del escritorio
// (Windows) — bypasea por completo los paquetes `firebase_auth`/
// `cloud_firestore` para lo que de verdad importa (mantener una sesión con
// token válido y leer/escribir Firestore), porque `firebase_auth` en
// Windows tiene un bug real y reproducible (confirmado 2026-09-18, con
// reportes iguales de otros desarrolladores en GitHub): después de
// `signInWithCredential`, no logra emitir un ID token utilizable
// (`[firebase_auth/unknown-error] An internal error has occurred`) — sin
// token, Firestore rechaza todo como si no hubiera nadie logueado. La
// causa no es de red (confirmado: los mismos endpoints responden bien
// desde `http` acá), es del SDK nativo de Windows, todavía nuevo.
//
// La companion Android NO usa nada de este archivo — el plugin nativo le
// funciona bien ahí (plataforma madura, sin este bug). Este archivo es
// puramente Dart/HTTP, sin ninguna dependencia de `firebase_auth`/
// `cloud_firestore` — evita arrastrar el mismo bug por reusar su capa de
// transporte interna.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'repositorio_sincronizacion.dart';

const _claveRefreshToken = 'firebase_rest_refresh_token';

class FirebaseRestException implements Exception {
  const FirebaseRestException(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Sesión activa contra Firebase por REST — mantiene el ID token fresco
/// (se renueva solo, un minuto antes de vencer) y expone el email/uid para
/// mostrar en la UI, sin depender de `FirebaseAuth.instance` en absoluto.
class SesionFirebaseRest {
  // Nombres de parámetro distintos a los campos a propósito (más claro
  // desde los call sites: `idToken:`, no el nombre privado del campo).
  SesionFirebaseRest._({
    required String idToken,
    required String refreshToken,
    required this.uid,
    required this.email,
    required DateTime expiraEn,
  }) : _idToken = idToken, // ignore: prefer_initializing_formals
       _refreshToken = refreshToken, // ignore: prefer_initializing_formals
       _expiraEn = expiraEn; // ignore: prefer_initializing_formals

  final String uid;
  final String email;

  String _idToken;
  String _refreshToken;
  DateTime _expiraEn;

  /// Token válido para usar YA — lo renueva solo si está por vencer (menos
  /// de un minuto de margen, para no arriesgar un pedido en vuelo que
  /// llegue justo después del vencimiento).
  Future<String> tokenValido() async {
    if (DateTime.now().isBefore(_expiraEn.subtract(const Duration(minutes: 1)))) {
      return _idToken;
    }
    await _renovar();
    return _idToken;
  }

  Future<void> _renovar() async {
    final respuesta = await http.post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=${DefaultFirebaseOptions.windows.apiKey}'),
      body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken},
    );
    final cuerpo = _decodificar(respuesta);
    _idToken = cuerpo['id_token'] as String;
    _refreshToken = cuerpo['refresh_token'] as String;
    _expiraEn = DateTime.now().add(Duration(seconds: int.parse(cuerpo['expires_in'] as String)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveRefreshToken, _refreshToken);
  }
}

SesionFirebaseRest? _sesionActual;
SesionFirebaseRest? get sesionRestActual => _sesionActual;

final _cambiosDeSesionController = StreamController<SesionFirebaseRest?>.broadcast();

/// Emite cada vez que la sesión REST se establece o se cierra — esto es lo
/// que dispara/corta la sincronización en el escritorio (`main.dart`), en
/// vez de `FirebaseAuth.instance.authStateChanges()` (que también depende
/// del plugin roto para lo que overall importa).
Stream<SesionFirebaseRest?> get cambiosDeSesionRest => _cambiosDeSesionController.stream;

/// Intercambia un ID token de Google (ya obtenido por
/// `autenticacion_escritorio.dart`) por una sesión de Firebase — mismo
/// resultado que `signInWithCredential`, pero por REST, sin tocar el
/// plugin nativo para nada de esto.
Future<SesionFirebaseRest> iniciarSesionRestConGoogle(String googleIdToken) async {
  final respuesta = await http.post(
    Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${DefaultFirebaseOptions.windows.apiKey}',
    ),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'postBody': 'id_token=$googleIdToken&providerId=google.com',
      'requestUri': 'http://localhost',
      'returnIdpCredential': true,
      'returnSecureToken': true,
    }),
  );
  final cuerpo = _decodificar(respuesta);
  final sesion = SesionFirebaseRest._(
    idToken: cuerpo['idToken'] as String,
    refreshToken: cuerpo['refreshToken'] as String,
    uid: cuerpo['localId'] as String,
    email: cuerpo['email'] as String,
    expiraEn: DateTime.now().add(Duration(seconds: int.parse(cuerpo['expiresIn'] as String))),
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_claveRefreshToken, sesion._refreshToken);
  _sesionActual = sesion;
  _cambiosDeSesionController.add(sesion);
  return sesion;
}

/// Al arrancar la app: si hay un refresh token guardado de una sesión
/// anterior, lo usa para conseguir un ID token nuevo sin volver a pasar por
/// el navegador. `null` si nunca se conectó, o si el refresh token ya no
/// sirve (revocado, etc. — en ese caso también lo borra).
Future<SesionFirebaseRest?> restaurarSesionRestGuardada() async {
  final prefs = await SharedPreferences.getInstance();
  final refreshToken = prefs.getString(_claveRefreshToken);
  if (refreshToken == null) return null;
  try {
    final respuesta = await http.post(
      Uri.parse('https://securetoken.googleapis.com/v1/token?key=${DefaultFirebaseOptions.windows.apiKey}'),
      body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    final cuerpo = _decodificar(respuesta);
    // La respuesta de refresh usa snake_case (distinto a signInWithIdp) y
    // no trae email — hace falta pedirlo aparte con el ID token nuevo.
    final idToken = cuerpo['id_token'] as String;
    final datosUsuario = await _consultarCuenta(idToken);
    final sesion = SesionFirebaseRest._(
      idToken: idToken,
      refreshToken: cuerpo['refresh_token'] as String,
      uid: cuerpo['user_id'] as String,
      email: datosUsuario,
      expiraEn: DateTime.now().add(Duration(seconds: int.parse(cuerpo['expires_in'] as String))),
    );
    await prefs.setString(_claveRefreshToken, sesion._refreshToken);
    _sesionActual = sesion;
    _cambiosDeSesionController.add(sesion);
    return sesion;
  } catch (_) {
    await prefs.remove(_claveRefreshToken);
    return null;
  }
}

Future<String> _consultarCuenta(String idToken) async {
  final respuesta = await http.post(
    Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${DefaultFirebaseOptions.windows.apiKey}',
    ),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'idToken': idToken}),
  );
  final cuerpo = _decodificar(respuesta);
  final usuarios = cuerpo['users'] as List<dynamic>;
  return (usuarios.first as Map<String, dynamic>)['email'] as String;
}

Future<void> cerrarSesionRest() async {
  _sesionActual = null;
  _cambiosDeSesionController.add(null);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_claveRefreshToken);
}

Map<String, dynamic> _decodificar(http.Response respuesta) {
  final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
  if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
    final error = cuerpo['error'] as Map<String, dynamic>?;
    throw FirebaseRestException('Firebase (${respuesta.statusCode}): ${error?['message'] ?? respuesta.body}');
  }
  return cuerpo;
}

// --- Firestore por REST ---
//
// Mismo negocio fijo que `transporte_firestore.dart` (Bruno no tiene ni va
// a tener más de un local). Sin listener en tiempo real por REST (Firestore
// sí lo ofrece, pero implementar el streaming de `Listen` a mano es mucho
// más trabajo que lo que esto necesita) — en cambio, sondeo periódico con
// cursor por tabla (mismo patrón que ya usaba el sync viejo por HTTP,
// `lib/companion/servicio_sincronizacion.dart`): solo trae lo nuevo desde
// la última vez, así que el costo en lecturas es proporcional a lo que
// cambió, no al tamaño total de la base.

const _negocioIdRest = 'la-plazoleta';
String get _baseFirestore =>
    'https://firestore.googleapis.com/v1/projects/${DefaultFirebaseOptions.windows.projectId}/databases/(default)/documents';

String _clavePullRest(String tabla) => 'firestore_rest_pull_$tabla';

/// Mismo límite que la versión nativa (`transporte_firestore.dart`) — un
/// solo `:commit` acepta hasta 500 escrituras.
const _maximoOperacionesPorLote = 450;

/// Sube [filas] con `:commit` (varias escrituras por pedido HTTP) en vez de
/// un PATCH por fila — la primera versión de esto mandaba una fila a la vez
/// y tardaba varios minutos con el historial real de Bruno (~1100 filas);
/// en lotes es la misma cantidad de datos con una fracción de los viajes de
/// ida y vuelta.
Future<void> subirFilasRest(SesionFirebaseRest sesion, String tabla, List<Map<String, dynamic>> filas) async {
  if (filas.isEmpty) return;
  final token = await sesion.tokenValido();
  final nombreProyecto = 'projects/${DefaultFirebaseOptions.windows.projectId}/databases/(default)/documents';

  for (var inicio = 0; inicio < filas.length; inicio += _maximoOperacionesPorLote) {
    final tanda = filas.skip(inicio).take(_maximoOperacionesPorLote);
    final escrituras = [
      for (final fila in tanda)
        {
          'update': {
            'name': '$nombreProyecto/negocios/$_negocioIdRest/$tabla/${fila['global_id']}',
            'fields': _aCamposFirestore(fila),
          },
        },
    ];
    final respuesta = await http.post(
      Uri.parse('$_baseFirestore:commit'),
      headers: {'Authorization': 'Bearer $token', 'content-type': 'application/json'},
      body: jsonEncode({'writes': escrituras}),
    );
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw FirebaseRestException('Firestore commit $tabla (${respuesta.statusCode}): ${respuesta.body}');
    }
  }
}

/// Filas de [tabla] con el cursor (`actualizado_en` o `id`, según
/// [tablasSincronizables]) mayor o igual al último visto — guarda su propio
/// cursor en SharedPreferences, separado del cursor de push (que vive del
/// lado de la base local, en `sincronizacion_firestore.dart`).
Future<List<Map<String, dynamic>>> descargarCambiosRest(SesionFirebaseRest sesion, String tabla) async {
  final prefs = await SharedPreferences.getInstance();
  final columnaCursor = tablasSincronizables[tabla]! ? 'actualizado_en' : 'id';
  final desde = prefs.getInt(_clavePullRest(tabla)) ?? 0;
  final token = await sesion.tokenValido();

  final respuesta = await http.post(
    Uri.parse('$_baseFirestore/negocios/$_negocioIdRest:runQuery'),
    headers: {'Authorization': 'Bearer $token', 'content-type': 'application/json'},
    body: jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': tabla},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': columnaCursor},
            'op': 'GREATER_THAN_OR_EQUAL',
            'value': {'integerValue': desde.toString()},
          },
        },
        'orderBy': [
          {'field': {'fieldPath': columnaCursor}, 'direction': 'ASCENDING'},
        ],
      },
    }),
  );
  if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
    throw FirebaseRestException('Firestore runQuery $tabla (${respuesta.statusCode}): ${respuesta.body}');
  }
  final resultados = jsonDecode(respuesta.body) as List<dynamic>;
  final filas = [
    for (final entrada in resultados)
      if ((entrada as Map<String, dynamic>)['document'] != null)
        _desdeCamposFirestore((entrada['document'] as Map<String, dynamic>)['fields'] as Map<String, dynamic>),
  ];
  if (filas.isNotEmpty) {
    final maximo = filas
        .map((f) => (f[columnaCursor] as num?)?.toInt() ?? 0)
        .reduce((a, b) => a > b ? a : b);
    await prefs.setInt(_clavePullRest(tabla), maximo);
  }
  return filas;
}

/// Documento fijo (no una fila de una tabla sincronizable) con las
/// credenciales de cobro por terminal Point — separado a propósito del
/// motor genérico de 14 tablas (Bruno, 2026-09-18: "quiero que ande sin la
/// PC" para el cobro por Point): es un token de pago, no un dato de
/// catálogo, así que viaja solo, en su propio documento, nunca mezclado con
/// el resto de `configuracion_tabla`.
const _rutaConfigCobro = 'configuracion/cobro';

Future<void> escribirConfigCobroRest(
  SesionFirebaseRest sesion, {
  required String? mpAccessToken,
  required String? mpTerminalCobroId,
}) async {
  final token = await sesion.tokenValido();
  final respuesta = await http.patch(
    Uri.parse('$_baseFirestore/negocios/$_negocioIdRest/$_rutaConfigCobro'),
    headers: {'Authorization': 'Bearer $token', 'content-type': 'application/json'},
    body: jsonEncode({
      'fields': _aCamposFirestore({
        'mp_access_token': mpAccessToken,
        'mp_terminal_cobro_id': mpTerminalCobroId,
      }),
    }),
  );
  if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
    throw FirebaseRestException(
      'Firestore patch configuracion/cobro (${respuesta.statusCode}): ${respuesta.body}',
    );
  }
}

/// `null` si el documento todavía no existe (celular recién logueado, antes
/// de que la PC haya sincronizado ni una vez).
Future<Map<String, dynamic>?> leerConfigCobroRest(SesionFirebaseRest sesion) async {
  final token = await sesion.tokenValido();
  final respuesta = await http.get(
    Uri.parse('$_baseFirestore/negocios/$_negocioIdRest/$_rutaConfigCobro'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (respuesta.statusCode == 404) return null;
  if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
    throw FirebaseRestException(
      'Firestore get configuracion/cobro (${respuesta.statusCode}): ${respuesta.body}',
    );
  }
  final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
  final campos = cuerpo['fields'] as Map<String, dynamic>?;
  return campos == null ? null : _desdeCamposFirestore(campos);
}

/// Convierte una fila cruda (la misma forma que ya usa
/// `repositorio_sincronizacion.dart`, snake_case, valores SQL crudos) al
/// formato de valores tipados que exige la API REST de Firestore.
Map<String, dynamic> _aCamposFirestore(Map<String, dynamic> fila) {
  return fila.map((clave, valor) => MapEntry(clave, _valorAFirestore(valor)));
}

Map<String, dynamic> _valorAFirestore(Object? valor) {
  if (valor == null) return {'nullValue': null};
  if (valor is int) return {'integerValue': valor.toString()};
  if (valor is double) return {'doubleValue': valor};
  if (valor is bool) return {'booleanValue': valor};
  return {'stringValue': valor.toString()};
}

Map<String, dynamic> _desdeCamposFirestore(Map<String, dynamic> campos) {
  return campos.map((clave, valor) => MapEntry(clave, _valorDesdeFirestore(valor as Map<String, dynamic>)));
}

Object? _valorDesdeFirestore(Map<String, dynamic> valorTipado) {
  if (valorTipado.containsKey('integerValue')) return int.parse(valorTipado['integerValue'] as String);
  if (valorTipado.containsKey('doubleValue')) return (valorTipado['doubleValue'] as num).toDouble();
  if (valorTipado.containsKey('booleanValue')) return valorTipado['booleanValue'] as bool;
  if (valorTipado.containsKey('stringValue')) return valorTipado['stringValue'] as String;
  return null; // nullValue, o un tipo que esta app nunca guarda (array/map)
}
