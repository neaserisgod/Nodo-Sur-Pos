// La cuenta de Nodo Sur vinculada a esta PC y el cliente de su API (horsepos.com): vincular, avisar que la PC
// está viva, subir y bajar copias de la base. Nada de esto toca la base del comercio: el token vive en un archivo
// aparte (si vivía en la base, restaurar una copia lo pisaría), y cualquier falla es un error tipado que la
// pantalla muestra sin romper la caja. Vender nunca depende de esto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as h;

import 'package:path/path.dart' as p;

import '../domain/avisos_mp.dart';
import '../domain/conciliacion_mp.dart';
import '../domain/saldo_mp.dart';
import '../domain/vinculacion.dart';
import 'avisos_cobro_mp.dart';
import 'registro_errores.dart';

/// Lo que guarda la PC después de vincularse.
/// La persona detrás de una cuenta vinculada: `rol` es 'owner' | 'manager' | 'employee' (null si el dispositivo es de antes
/// del modelo de negocios).
class PerfilDeCuenta {
  const PerfilDeCuenta({required this.email, required this.nombre, this.rol});
  final String email;
  final String nombre;
  final String? rol;
}

class CuentaVinculada {
  const CuentaVinculada({
    required this.token,
    required this.email,
    required this.idDispositivo,
    required this.nombreDispositivo,
    required this.vence,
  });

  /// Token de dispositivo (1 año, se renueva solo con cada aviso).
  final String token;
  final String email;
  final String idDispositivo;
  final String nombreDispositivo;

  /// Segundos desde la época, como lo informa el servidor.
  final int vence;

  CuentaVinculada conToken(String nuevo, {int? vence}) => CuentaVinculada(
    token: nuevo,
    email: email,
    idDispositivo: idDispositivo,
    nombreDispositivo: nombreDispositivo,
    vence: vence ?? this.vence,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'email': email,
    'idDispositivo': idDispositivo,
    'nombreDispositivo': nombreDispositivo,
    'vence': vence,
  };

  static CuentaVinculada? desdeJson(Object? j) {
    if (j is! Map) return null;
    final token = j['token'], email = j['email'], id = j['idDispositivo'];
    if (token is! String || email is! String || id is! String) return null;
    return CuentaVinculada(
      token: token,
      email: email,
      idDispositivo: id,
      nombreDispositivo: j['nombreDispositivo'] is String ? j['nombreDispositivo'] as String : 'Mi PC',
      vence: j['vence'] is int ? j['vence'] as int : 0,
    );
  }
}

abstract class AlmacenCuenta {
  Future<CuentaVinculada?> leer();
  Future<void> guardar(CuentaVinculada cuenta);
  Future<void> borrar();
}

class AlmacenCuentaEnMemoria implements AlmacenCuenta {
  CuentaVinculada? _cuenta;
  @override
  Future<CuentaVinculada?> leer() async => _cuenta;
  @override
  Future<void> guardar(CuentaVinculada cuenta) async => _cuenta = cuenta;
  @override
  Future<void> borrar() async => _cuenta = null;
}

/// Un archivo JSON en la carpeta de datos de la app. Un archivo roto o ausente es "sin vincular", nunca un error.
class AlmacenCuentaEnArchivo implements AlmacenCuenta {
  AlmacenCuentaEnArchivo(this.carpeta);
  final String carpeta;

  File get _archivo => File(p.join(carpeta, 'nodosur_cuenta.json'));

  @override
  Future<CuentaVinculada?> leer() async {
    try {
      if (!await _archivo.exists()) return null;
      return CuentaVinculada.desdeJson(jsonDecode(await _archivo.readAsString()));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar(CuentaVinculada cuenta) async {
    await Directory(carpeta).create(recursive: true);
    // Se escribe a un temporal y se renombra: un corte a mitad de camino no deja el token a medias.
    final temporal = File('${_archivo.path}.tmp');
    await temporal.writeAsString(jsonEncode(cuenta.toJson()), flush: true);
    await temporal.rename(_archivo.path);
  }

  @override
  Future<void> borrar() async {
    try {
      if (await _archivo.exists()) await _archivo.delete();
    } catch (e, pila) {
      // Desvincular sin poder borrar deja el token en disco: que quede anotado.
      await registrarError('Borrar la cuenta de Nodo Sur vinculada', e, pila);
    }
  }
}

/// Una falla del servicio, con un texto que se puede mostrar tal cual.
class ErrorNube implements Exception {
  const ErrorNube(this.codigo, this.mensaje, {this.estado});

  /// Código del servidor (`no_upload`, `hash_mismatch`…) o uno propio (`sin_red`, `vinculacion_cancelada`).
  final String codigo;
  final String mensaje;
  final int? estado;

  /// La sesión del dispositivo ya no vale (se desvinculó desde el sitio o venció): hay que volver a vincular.
  bool get pideVincularDeNuevo => estado == 401;

  @override
  String toString() => mensaje;
}

String _mensajeDe(String codigo) => switch (codigo) {
  'no_device' || 'no_session' => 'Esta PC ya no está vinculada a la cuenta. Volvé a vincularla.',
  'no_upload' => 'Tu suscripción no está activa: por ahora solo podés restaurar copias, no guardar nuevas.',
  'no_restore' => 'No hay copias disponibles para restaurar con esta cuenta.',
  'backups_no_configurados' => 'El servicio de copias todavía no está listo. Probá más tarde.',
  'mp_error' => 'No se pudo comprobar la suscripción en este momento. Probá más tarde.',
  'sync_no_configurada' => 'La sincronización por internet todavía no está lista. Probá más tarde.',
  'too_large' => 'La base es demasiado grande para subirla.',
  'hash_mismatch' => 'La copia se dañó en el camino. Probá de nuevo.',
  'not_found' => 'Esa copia ya no existe.',
  'corrupt' => 'Esa copia no se pudo recuperar del servidor.',
  'mp_no_conectado' => 'Mercado Pago todavía no está conectado: el dueño lo conecta en horsepos.com/negocio.',
  'mp_sin_terminal' => 'Esta sucursal no tiene una terminal elegida: el dueño la elige en horsepos.com/negocio.',
  'mp_no_configurado' => 'La conexión con Mercado Pago todavía no está lista en el servidor. Probá más tarde.',
  'sin_negocio' => 'Este dispositivo no pertenece a ningún negocio: volvé a vincularlo con tu cuenta.',
  'mp_rechazo' => 'Mercado Pago rechazó el pedido.',
  'sin_permiso_devolver' => 'Devolver por Mercado Pago lo pueden hacer el dueño o el encargado.',
  'ya_devuelta' => 'Ese cobro ya estaba devuelto.',
  'no_cobrada' => 'Ese cobro no figura como cobrado en Mercado Pago: no hay nada para devolver.',
  _ => 'El servicio respondió con un error ($codigo).',
};

/// Lo que el servidor dice sobre cobrar con la terminal desde este dispositivo.
class EstadoMp {
  const EstadoMp({required this.conectado, required this.necesitaReconectar, required this.terminalElegida, this.puedeDevolver = false});
  final bool conectado;
  final bool necesitaReconectar;
  final bool terminalElegida;

  /// Si la persona que vinculó este equipo puede devolver por Mercado Pago (dueño y encargado, etapa B). Solo sirve para
  /// ofrecer o no la devolución: quien decide es el sitio al devolver.
  final bool puedeDevolver;

  bool get puedeCobrar => conectado && terminalElegida;
}

class CopiaEnNube {
  const CopiaEnNube({
    required this.id,
    required this.creada,
    required this.tamanio,
    required this.sha256,
    required this.schemaVersion,
    required this.appVersion,
    required this.nombreDispositivo,
  });

  final int id;
  final DateTime creada;
  final int tamanio;
  final String sha256;
  final int? schemaVersion;
  final String? appVersion;
  final String? nombreDispositivo;

  static CopiaEnNube desdeJson(Map<String, dynamic> j) => CopiaEnNube(
    id: (j['id'] as num).toInt(),
    creada: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt() * 1000),
    tamanio: (j['size'] as num?)?.toInt() ?? 0,
    sha256: (j['sha256'] as String?) ?? '',
    schemaVersion: (j['schemaVersion'] as num?)?.toInt(),
    appVersion: j['appVersion'] as String?,
    nombreDispositivo: j['deviceName'] as String?,
  );
}

class EstadoCopias {
  const EstadoCopias({required this.puedeSubir, required this.puedeRestaurar, required this.maximo, required this.copias, this.sinPermiso = false});
  final bool puedeSubir;
  final bool puedeRestaurar;

  /// El rol de esta cuenta no administra copias (un empleado): no es falta de suscripción, el negocio sí la tiene.
  final bool sinPermiso;
  final int maximo;
  final List<CopiaEnNube> copias;
}

class RespuestaAviso {
  const RespuestaAviso({required this.canal, this.tokenNuevo});

  /// 'beta' para el administrador (recibe las versiones de prueba antes), 'stable' para el resto.
  final String canal;

  /// Si al token le quedaban menos de 60 días, el servidor manda uno nuevo.
  final String? tokenNuevo;
}

/// Un lote bajado tal como lo manda el servidor (los bytes ya vienen descifrados, siguen comprimidos).
class LoteRecibido {
  const LoteRecibido({required this.seq, required this.deviceId, required this.creadoEn, required this.bytes});
  final int seq;
  final String deviceId;

  /// Hora del servidor (segundos) en que llegó el lote.
  final int creadoEn;
  final List<int> bytes;
}

class RespuestaBajada {
  const RespuestaBajada({required this.lotes, required this.hasta, required this.mas}) : expirada = false;

  /// El servidor ya no guarda lo que este dispositivo se perdió.
  const RespuestaBajada.expirada()
      : lotes = const [],
        hasta = 0,
        mas = false,
        expirada = true;

  final List<LoteRecibido> lotes;

  /// Cursor para el próximo pedido (avanza también sobre los lotes propios, que no se devuelven).
  final int hasta;

  /// Quedan más lotes por bajar.
  final bool mas;
  final bool expirada;
}

/// Abre la conexión de avisos. Se inyecta para probar sin red: devuelve lo que llega por el socket.
typedef AbrirEscucha = Future<Stream<dynamic>> Function(Uri uri, Map<String, String> cabeceras);

Future<Stream<dynamic>> _abrirWebSocket(Uri uri, Map<String, String> cabeceras) async {
  final socket = await WebSocket.connect(uri.toString(), headers: cabeceras).timeout(const Duration(seconds: 20));
  // Ping del protocolo (no se cobra y lo contesta el borde de Cloudflare): si la red se cae sin avisar, el socket
  // se cierra solo en vez de quedar "conectado" sin recibir nunca nada.
  socket.pingInterval = const Duration(seconds: 45);
  return socket;
}

class ClienteNube {
  ClienteNube({required this.http, this.host = hostNodoSur, this.esquema = 'https', this.puerto, AbrirEscucha? abrirEscucha})
      : _abrirEscucha = abrirEscucha ?? _abrirWebSocket;

  final AbrirEscucha _abrirEscucha;
  final h.Client http;
  final String host;
  final String esquema;
  final int? puerto;

  static const _limite = Duration(seconds: 30);

  Uri _uri(String ruta, [Map<String, String>? consulta]) =>
      Uri(scheme: esquema, host: host, port: puerto, path: ruta, queryParameters: consulta);

  Map<String, String> _auth(String token, [Map<String, String> extra = const {}]) => {'Authorization': 'Bearer $token', ...extra};

  Never _falla(int estado, String cuerpo) {
    var codigo = 'http_$estado';
    String? motivo;
    try {
      final j = jsonDecode(cuerpo);
      if (j is Map && j['error'] is String) codigo = j['error'] as String;
      // Un rechazo de Mercado Pago trae su propio código y motivo: se muestran tal cual para poder diagnosticarlo.
      if (j is Map && j['mensaje'] is String) motivo = j['mensaje'] as String;
    } catch (_) {}
    final propio = motivo == null ? _mensajeDe(codigo) : 'Mercado Pago respondió ($estado): $motivo';
    throw ErrorNube(codigo, propio, estado: estado);
  }

  Future<T> _conRed<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(const Duration(minutes: 3));
    } on ErrorNube {
      rethrow;
    } on TimeoutException {
      throw const ErrorNube('sin_red', 'No hay conexión con el servidor. Probá de nuevo en un rato.');
    } on SocketException {
      throw const ErrorNube('sin_red', 'No hay conexión con el servidor. Probá de nuevo en un rato.');
    } on h.ClientException {
      throw const ErrorNube('sin_red', 'No hay conexión con el servidor. Probá de nuevo en un rato.');
    }
  }

  /// Paso final de la vinculación: cambia el código de un solo uso por el token del dispositivo.
  Future<CuentaVinculada> canjear({required String code, required String verificador, required String nombre}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/device/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'verifier': verificador}),
    ).timeout(_limite);
    if (r.statusCode != 200) {
      if (r.statusCode == 400) throw ErrorNube('invalid_code', 'La vinculación no se pudo completar. Volvé a intentarla.', estado: 400);
      _falla(r.statusCode, r.body);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return CuentaVinculada(
      token: j['token'] as String,
      email: j['email'] as String,
      idDispositivo: j['deviceId'] as String,
      nombreDispositivo: nombre,
      vence: (j['expiresAt'] as num?)?.toInt() ?? 0,
    );
  });

  /// Quién es la persona que vinculó este dispositivo (nombre de su cuenta, rol y sucursal). El celular lo usa para tomar su
  /// perfil de la cuenta en vez de elegirlo de una lista.
  Future<PerfilDeCuenta> yo(String token) => _conRed(() async {
    final r = await http.get(_uri('/api/device/me'), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return PerfilDeCuenta(email: j['email'] as String, nombre: (j['name'] as String).trim(), rol: j['role'] as String?);
  });

  // ─── Cobro con la terminal Point a través del servidor (el token de Mercado Pago del negocio no sale de ahí) ───

  /// Si el negocio de este dispositivo puede cobrar por el servidor: Mercado Pago conectado y terminal elegida para su sucursal.
  Future<EstadoMp> estadoMp(String token) => _conRed(() async {
    final r = await http.get(_uri('/api/mp/estado'), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return EstadoMp(
      conectado: j['connected'] == true,
      necesitaReconectar: j['needsReconnect'] == true,
      terminalElegida: j['terminalConfigured'] == true,
      puedeDevolver: j['canRefund'] == true,
    );
  });

  /// Crea la orden en la terminal. [idempotencyKey] repetida no duplica el cobro (mismo criterio que el cobro directo).
  Future<({String id, String estado})> crearOrdenPoint(
    String token, {
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  }) => _conRed(() async {
    final r = await http.post(
      _uri('/api/mp/orden'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'externalReference': externalReference, 'idempotencyKey': idempotencyKey, 'montoCentavos': montoCentavos, 'canal': canal}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final id = j['id']?.toString();
    final estado = j['status']?.toString();
    if (id == null || estado == null) throw const ErrorNube('respuesta_invalida', 'Mercado Pago respondió sin id o estado de la orden.');
    return (id: id, estado: estado);
  });

  Future<String> consultarOrdenPoint(String token, String ordenIdMp) => _conRed(() async {
    final r = await http.get(_uri('/api/mp/orden', {'id': ordenIdMp}), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final estado = (jsonDecode(r.body) as Map<String, dynamic>)['status']?.toString();
    if (estado == null) throw const ErrorNube('respuesta_invalida', 'Mercado Pago respondió sin el estado de la orden.');
    return estado;
  });

  /// Los cobros que Mercado Pago dice que entraron a la cuenta del negocio entre [desde] y [hasta] (para el cierre).
  Future<({List<CobroMp> cobros, bool truncado})> cobrosMp(String token, {required DateTime desde, required DateTime hasta}) => _conRed(() async {
    final r = await http.get(
      _uri('/api/mp/cobros', {'desde': '${desde.millisecondsSinceEpoch ~/ 1000}', 'hasta': '${hasta.millisecondsSinceEpoch ~/ 1000}'}),
      headers: _auth(token),
    ).timeout(_limite);
    if (r.statusCode != 200) {
      if (r.statusCode == 502 && !r.body.contains('"mensaje":"')) {
        throw ErrorNube('mp_error', 'Mercado Pago no respondió con los cobros. Probá de nuevo en un rato.', estado: r.statusCode);
      }
      _falla(r.statusCode, r.body);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    DateTime? fecha(Object? s) => s is num ? DateTime.fromMillisecondsSinceEpoch(s.toInt() * 1000) : null;
    int n(Object? x) => (x as num?)?.toInt() ?? 0;
    final cobros = [
      for (final c in (j['cobros'] as List? ?? const []).cast<Map<String, dynamic>>())
        CobroMp(
          id: '${c['id']}',
          estado: c['estado'] as String?,
          fecha: fecha(c['fecha']),
          montoCentavos: n(c['montoCentavos']),
          devueltoCentavos: n(c['devueltoCentavos']),
          comisionCentavos: n(c['comisionCentavos']),
          netoCentavos: n(c['netoCentavos']),
          medio: c['medio'] as String?,
          metodo: c['metodo'] as String?,
          referencia: c['referencia'] as String?,
        ),
    ];
    return (cobros: cobros, truncado: j['truncado'] == true);
  });

  /// Los avisos de cobros, contracargos y reclamos que el sitio guardó después de [desde] (el último id que esta PC ya tiene).
  /// Es lo que llegó con la PC apagada o sin conexión en vivo.
  Future<List<AvisoMp>> avisosMp(String token, {required int desde}) => _conRed(() async {
    final r = await http.get(_uri('/api/mp/avisos', {'desde': '$desde'}), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final avisos = <AvisoMp>[];
    for (final a in (j['avisos'] as List? ?? const []).whereType<Map>()) {
      final aviso = avisoMpDesdeJson(a.cast<String, dynamic>());
      if (aviso != null) avisos.add(aviso);
    }
    return avisos;
  });

  /// Pide el reporte de Liquidaciones de Mercado Pago desde [desde] hasta ahora (etapa E, saldo real del cierre). Tarda unos
  /// minutos: devuelve el id del pedido para preguntar con [estadoSaldoMp]. Pedirlo dos veces seguidas devuelve el mismo.
  Future<int> pedirSaldoMp(String token, {required DateTime desde}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/mp/saldo'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'desde': desde.millisecondsSinceEpoch ~/ 1000}),
    ).timeout(_limite);
    if (r.statusCode != 200) {
      if (r.statusCode == 502) throw ErrorNube('mp_error', 'Mercado Pago no aceptó el pedido del saldo. Probá de nuevo en un rato.', estado: r.statusCode);
      _falla(r.statusCode, r.body);
    }
    final id = (jsonDecode(r.body) as Map<String, dynamic>)['id'];
    if (id is! num) throw const ErrorNube('respuesta_invalida', 'El sitio respondió sin el número del pedido.');
    return id.toInt();
  });

  /// Cómo va el pedido del saldo: todavía se arma, falló, o está listo.
  Future<EstadoSaldoMp> estadoSaldoMp(String token, int id) => _conRed(() async {
    final r = await http.get(_uri('/api/mp/saldo', {'id': '$id'}), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) {
      if (r.statusCode == 502) throw ErrorNube('mp_error', 'Mercado Pago no respondió con el saldo. Probá de nuevo en un rato.', estado: r.statusCode);
      _falla(r.statusCode, r.body);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return switch (j['estado']) {
      'listo' => EstadoSaldoMp.listo(_saldoDesdeJson(j)),
      'error' => EstadoSaldoMp.fallo(j['motivo'] as String?),
      _ => const EstadoSaldoMp.pendiente(),
    };
  });

  /// Manda un ticket a la terminal de la sucursal por el servidor (el token de Mercado Pago no sale de ahí).
  Future<void> imprimirTicketPoint(String token, {required String externalReference, required String idempotencyKey, required String contenido}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/mp/imprimir'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'externalReference': externalReference, 'idempotencyKey': idempotencyKey, 'contenido': contenido}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
  });

  /// Devuelve al cliente lo cobrado por una orden (etapa B). Total: el monto lo sabe Mercado Pago. [idempotencyKey] es fija por
  /// venta, así reintentar nunca devuelve dos veces. Lanza [ErrorNube] con `sin_permiso_devolver`, `ya_devuelta` o `no_cobrada`.
  Future<String?> devolverOrdenPoint(String token, String ordenIdMp, {required String idempotencyKey}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/mp/orden/devolver'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'id': ordenIdMp, 'idempotencyKey': idempotencyKey}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    return (jsonDecode(r.body) as Map<String, dynamic>)['status'] as String?;
  });

  Future<void> cancelarOrdenPoint(String token, String ordenIdMp) => _conRed(() async {
    final r = await http.post(
      _uri('/api/mp/orden/cancelar'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'id': ordenIdMp}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
  });

  /// La PC avisa dónde está en el wifi del local (y la llave de su servidor para celulares), para que un celular de la
  /// misma sucursal se conecte con un toque.
  Future<void> publicarPcLocal(String token, {required String ip, required int puerto, required String llave}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/device/pc-local'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'ip': ip, 'puerto': puerto, 'token': llave}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
  });

  /// La PC del local de la sucursal de este celular, o null si ninguna avisó todavía.
  Future<({String ip, int puerto, String llave, String? nombre})?> pcLocal(String token) => _conRed(() async {
    final r = await http.get(_uri('/api/device/pc-local'), headers: _auth(token)).timeout(_limite);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (ip: j['ip'] as String, puerto: (j['puerto'] as num).toInt(), llave: j['token'] as String, nombre: j['nombre'] as String?);
  });

  Future<RespuestaAviso> avisar(String token, {required String cid, required String version, required String sistema}) => _conRed(() async {
    final r = await http.post(
      _uri('/api/device/ping'),
      headers: _auth(token, {'Content-Type': 'application/json'}),
      body: jsonEncode({'cid': cid, 'version': version, 'os': sistema}),
    ).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RespuestaAviso(canal: (j['channel'] as String?) ?? 'stable', tokenNuevo: j['token'] as String?);
  });

  Future<EstadoCopias> estado(String token) => _conRed(() async {
    final r = await http.get(_uri('/api/backups'), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return EstadoCopias(
      puedeSubir: j['upload'] == true,
      puedeRestaurar: j['restore'] == true,
      sinPermiso: j['noPermission'] == true,
      maximo: (j['max'] as num?)?.toInt() ?? 5,
      copias: [for (final c in (j['backups'] as List? ?? const [])) CopiaEnNube.desdeJson(c as Map<String, dynamic>)],
    );
  });

  /// Sube una copia ya comprimida. [sha256] es el hex de [bytes].
  Future<({int id, int guardadas})> subir(
    String token, {
    required List<int> bytes,
    required String sha256,
    required int schemaVersion,
    required String appVersion,
  }) => _conRed(() async {
    final r = await http.put(
      _uri('/api/backup'),
      headers: _auth(token, {
        'Content-Type': 'application/octet-stream',
        'X-Sha256': sha256,
        'X-Schema-Version': '$schemaVersion',
        'X-App-Version': appVersion,
      }),
      body: bytes,
    ).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (id: (j['id'] as num).toInt(), guardadas: (j['guardadas'] as num?)?.toInt() ?? 0);
  });

  /// Sube un lote de cambios de la sync entre dispositivos. [loteId] hace que reintentar sea seguro: el servidor
  /// no guarda dos veces el mismo. [sha256] es el hex de [bytes] (ya comprimidos).
  Future<({int seq, bool repetido})> subirLote(
    String token, {
    required String loteId,
    required List<int> bytes,
    required String sha256,
  }) => _conRed(() async {
    final r = await http.post(
      _uri('/api/sync'),
      headers: _auth(token, {'Content-Type': 'application/octet-stream', 'X-Lote-Id': loteId, 'X-Sha256': sha256}),
      body: bytes,
    ).timeout(const Duration(minutes: 1));
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (seq: (j['seq'] as num).toInt(), repetido: j['repetido'] == true);
  });

  /// Se conecta a los avisos de la cuenta: cada elemento del stream es "otro dispositivo subió algo, andá a bajar".
  /// El stream termina cuando se corta la conexión. Lanza [ErrorNube] si no se pudo conectar.
  ///
  /// Por la misma conexión llegan los avisos de Mercado Pago sobre una orden de cobro (`{"mp":{"orden":…}}`, etapa A): esos
  /// no son "bajá datos", van a [avisarOrdenMp] para despertar al diálogo de cobro.
  Future<Stream<void>> escuchar(String token) async {
    try {
      final uri = Uri(scheme: esquema == 'https' ? 'wss' : 'ws', host: host, port: puerto, path: '/api/sync/escuchar');
      final mensajes = await _abrirEscucha(uri, _auth(token));
      avisarConexionEnVivoAbierta();
      return mensajes.where((m) => m is String && !_esAvisoOrdenMp(m)).map((_) {});
    } on TimeoutException {
      throw const ErrorNube('sin_red', 'No hay conexión con el servidor. Probá de nuevo en un rato.');
    } on SocketException {
      throw const ErrorNube('sin_red', 'No hay conexión con el servidor. Probá de nuevo en un rato.');
    } on WebSocketException catch (e) {
      throw ErrorNube('sin_escucha', 'No se pudo abrir el aviso en vivo: ${e.message}');
    }
  }

  /// Un aviso de orden de Mercado Pago se entrega a [avisarOrdenMp] y no cuenta como cambio de datos. Cualquier otra cosa (o
  /// algo que no se entiende) sigue siendo "bajá": ante la duda, sincronizar de más no rompe nada.
  static bool _esAvisoOrdenMp(String mensaje) {
    if (!mensaje.contains('"mp"')) return false;
    try {
      final j = jsonDecode(mensaje);
      final mp = j is Map ? j['mp'] : null;
      if (mp is Map && mp['aviso'] is Map) {
        final aviso = avisoMpDesdeJson((mp['aviso'] as Map).cast<String, dynamic>());
        if (aviso != null) avisarAvisoMp(aviso);
        return true; // un aviso que no se entiende tampoco es "bajá datos"
      }
      if (mp is! Map || mp['orden'] is! String) return false;
      avisarOrdenMp(mp['orden'] as String);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Baja los lotes que subieron los otros dispositivos, a partir de [desde] (el último `seq` ya visto).
  Future<RespuestaBajada> bajarLotes(String token, {required int desde}) => _conRed(() async {
    final r = await http.get(_uri('/api/sync', {'desde': '$desde'}), headers: _auth(token)).timeout(_limite);
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['expirado'] == true) return const RespuestaBajada.expirada();
    return RespuestaBajada(
      lotes: [
        for (final l in (j['lotes'] as List? ?? const []).cast<Map<String, dynamic>>())
          LoteRecibido(
            seq: (l['seq'] as num).toInt(),
            deviceId: l['deviceId'] as String,
            creadoEn: (l['creadoEn'] as num).toInt(),
            bytes: base64Decode(l['datos'] as String),
          ),
      ],
      hasta: (j['hasta'] as num?)?.toInt() ?? desde,
      mas: j['mas'] == true,
    );
  });

  /// Baja una copia propia. Devuelve los bytes y el hash que informó el servidor.
  Future<({List<int> bytes, String sha256, int? schemaVersion})> bajar(String token, int id) => _conRed(() async {
    final r = await http.get(_uri('/api/backup', {'id': '$id'}), headers: _auth(token)).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) _falla(r.statusCode, r.body);
    return (
      bytes: r.bodyBytes,
      sha256: r.headers['x-sha256'] ?? '',
      schemaVersion: int.tryParse(r.headers['x-schema-version'] ?? ''),
    );
  });
}

/// Abre la página de vinculación, espera el aviso en el servidor local y canjea el código. Devuelve la cuenta ya
/// guardada. [abrirNavegador] y [cliente] se inyectan para probarlo sin navegador ni red.
Future<CuentaVinculada> vincularEstaPc({
  required ClienteNube cliente,
  required AlmacenCuenta almacen,
  required String idDispositivo,
  required String nombre,
  required Future<void> Function(Uri) abrirNavegador,
  Duration espera = const Duration(minutes: 5),
  String host = hostNodoSur,
  bool celular = false,
}) async {
  final verificador = generarVerificador();
  final state = generarState();
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final codigo = Completer<String>();
  final escucha = servidor.listen((pedido) async {
    final code = codigoDeCallback(pedido.uri, stateEsperado: state);
    pedido.response.headers.contentType = ContentType.html;
    if (code == null) {
      pedido.response.statusCode = 400;
      pedido.response.write('<!doctype html><meta charset="utf-8"><p>Este enlace no es de esta vinculación.</p>');
    } else {
      pedido.response.write(
        '<!doctype html><meta charset="utf-8"><title>Nodo Sur POS</title>'
        '<body style="font-family:sans-serif;text-align:center;margin-top:15vh">'
        '<h2>${celular ? 'Listo, entraste en tu celular' : 'Listo, tu PC quedó vinculada'}</h2><p>Ya podés cerrar esta pestaña y volver a la app.</p></body>',
      );
      if (!codigo.isCompleted) codigo.complete(code);
    }
    await pedido.response.close();
  });
  try {
    await abrirNavegador(urlVincular(
      puerto: servidor.port,
      state: state,
      desafio: desafioDe(verificador),
      idDispositivo: idDispositivo,
      nombre: nombre,
      host: host,
      celular: celular,
    ));
    final code = await codigo.future.timeout(
      espera,
      onTimeout: () => throw const ErrorNube('vinculacion_cancelada', 'No se completó la vinculación a tiempo. Volvé a intentarlo.'),
    );
    final cuenta = await cliente.canjear(code: code, verificador: verificador, nombre: nombre);
    await almacen.guardar(cuenta);
    return cuenta;
  } finally {
    await escucha.cancel();
    await servidor.close(force: true);
  }
}

/// Un aviso del sitio (`/api/mp/avisos` o el aviso en vivo). null si no se entiende: un tipo nuevo de un sitio más nuevo no
/// tiene que romper nada.
AvisoMp? avisoMpDesdeJson(Map<String, dynamic> j) {
  final id = j['id'];
  final tipo = TipoAvisoMp.values.where((t) => t.name == j['tipo']).firstOrNull;
  final mpId = j['mpId'];
  if (id is! num || tipo == null || mpId is! String) return null;
  DateTime? fecha(Object? s) => s is num ? DateTime.fromMillisecondsSinceEpoch(s.toInt() * 1000) : null;
  return AvisoMp(
    idServidor: id.toInt(),
    tipo: tipo,
    mpId: mpId,
    pagoId: j['pagoId'] as String?,
    montoCentavos: (j['montoCentavos'] as num?)?.toInt(),
    referencia: j['referencia'] as String?,
    estado: j['estado'] as String?,
    detalle: j['detalle'] as String?,
    fecha: fecha(j['fecha']),
    creado: fecha(j['creado']) ?? DateTime.now(),
  );
}

/// Cómo va un pedido de saldo (etapa E).
class EstadoSaldoMp {
  const EstadoSaldoMp.pendiente() : saldo = null, motivo = null, _tipo = 0;
  const EstadoSaldoMp.listo(SaldoMp this.saldo) : motivo = null, _tipo = 1;
  const EstadoSaldoMp.fallo(this.motivo) : saldo = null, _tipo = 2;

  final SaldoMp? saldo;
  final String? motivo;
  final int _tipo;

  bool get pendiente => _tipo == 0;
  bool get listo => _tipo == 1;
  bool get fallo => _tipo == 2;
}

SaldoMp _saldoDesdeJson(Map<String, dynamic> j) {
  DateTime? fecha(Object? s) => s is num ? DateTime.fromMillisecondsSinceEpoch(s.toInt() * 1000) : null;
  int n(Object? x) => (x as num?)?.toInt() ?? 0;
  return SaldoMp(
    disponibleCentavos: n(j['saldoDisponibleCentavos']),
    aLiberarCentavos: (j['aLiberarCentavos'] as num?)?.toInt(),
    hasta: fecha(j['hasta']),
    truncado: j['truncado'] == true,
    movimientos: [
      for (final m in (j['movimientos'] as List? ?? const []).whereType<Map>())
        MovimientoSaldoMp(
          fecha: fecha(m['fecha']),
          tipo: '${m['tipo'] ?? ''}',
          descripcion: '${m['descripcion'] ?? ''}',
          creditoCentavos: n(m['creditoCentavos']),
          debitoCentavos: n(m['debitoCentavos']),
          referencia: m['referencia'] as String?,
          origen: m['origen'] as String?,
        ),
    ],
  );
}
