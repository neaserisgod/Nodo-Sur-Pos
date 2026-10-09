// Cliente HTTP de la companion app Android — le habla al servidor que corre
// embebido en la app de escritorio (`lib/servidor/servidor_companion.dart`)
// mientras esté abierta y en la misma red. El celular nunca toca una base
// de datos propia: todo lo que sabe es lo que este cliente le devuelve.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/cobro_posnet.dart' show ResultadoOrdenCobro, resultadoDesdeRespuesta;
import '../domain/descuento.dart' show TipoDescuento;
import '../servicios/registro_errores.dart';
import '../domain/edicion_masiva_precios.dart' show CampoMonto, TipoAjustePrecio;
import '../domain/edicion_masiva_stock.dart' show TipoAjusteStock;
import '../domain/venta.dart' show LineaVenta, ResultadoTotalVenta;
import '../domain/venta_json.dart' show lineaVentaAJson, lineaVentaDesdeJson;
import 'servicio_companion.dart';
import '../servicios/devolucion_mp.dart' show CobroPoint;

class DatosConexion {
  final String ip;
  final int puerto;
  final String token;

  const DatosConexion({
    required this.ip,
    required this.puerto,
    required this.token,
  });

  Uri _url(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: ip,
    port: puerto,
    path: path,
    queryParameters: query,
  );
}

/// Cualquier respuesta que no sea 2xx — el mensaje ya viene armado por el
/// servidor (`{"error": "..."}`, ver `servidor_companion.dart`), listo para
/// mostrar tal cual en pantalla.
class ErrorCompanion implements Exception {
  final int statusCode;
  final String mensaje;
  const ErrorCompanion(this.statusCode, this.mensaje);

  @override
  String toString() => mensaje;
}

class ProductoCompanion {
  final int id;
  final String nombre;
  final String? codigoBarras;
  final int? categoriaId;
  final int? proveedorId;
  final bool esPesable;
  final int? precioCentavos;
  final int? costoCentavos;
  final int? precioPorKiloCentavos;
  final int? costoPorKiloCentavos;
  final int stock;
  final int? stockGramos;
  final bool activo;

  /// `'ninguno'` | `'atado'` | `'suelto'` — necesario para armar la
  /// `LineaVenta` de una venta (recargo de cigarrillos, Regla 6), sin uso
  /// en Conteo/Precios.
  final String tipoCigarrillo;

  const ProductoCompanion({
    required this.id,
    required this.nombre,
    this.codigoBarras,
    this.categoriaId,
    this.proveedorId,
    required this.esPesable,
    this.precioCentavos,
    this.costoCentavos,
    this.precioPorKiloCentavos,
    this.costoPorKiloCentavos,
    required this.stock,
    this.stockGramos,
    required this.activo,
    this.tipoCigarrillo = 'ninguno',
  });

  factory ProductoCompanion.desdeJson(Map<String, dynamic> j) =>
      ProductoCompanion(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        codigoBarras: j['codigoBarras'] as String?,
        categoriaId: j['categoriaId'] as int?,
        proveedorId: j['proveedorId'] as int?,
        esPesable: j['esPesable'] as bool,
        precioCentavos: j['precioCentavos'] as int?,
        costoCentavos: j['costoCentavos'] as int?,
        precioPorKiloCentavos: j['precioPorKiloCentavos'] as int?,
        costoPorKiloCentavos: j['costoPorKiloCentavos'] as int?,
        stock: j['stock'] as int,
        stockGramos: j['stockGramos'] as int?,
        activo: j['activo'] as bool,
        tipoCigarrillo: j['tipoCigarrillo'] as String? ?? 'ninguno',
      );
}

class ProveedorCompanion {
  final int id;
  final String codigo;
  final String nombre;
  const ProveedorCompanion({
    required this.id,
    required this.codigo,
    required this.nombre,
  });

  factory ProveedorCompanion.desdeJson(Map<String, dynamic> j) =>
      ProveedorCompanion(
        id: j['id'] as int,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
      );
}

class CategoriaCompanion {
  final int id;
  final String nombre;

  /// Basis points, ej. 1500 = 15% — puramente informativo (Regla 14: nunca
  /// se usa para calcular ni completar un precio). Editable desde
  /// Configuración en la companion (El dueño, 2026-09-19).
  final int markupDefaultBp;

  const CategoriaCompanion({
    required this.id,
    required this.nombre,
    this.markupDefaultBp = 0,
  });

  factory CategoriaCompanion.desdeJson(Map<String, dynamic> j) => CategoriaCompanion(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    markupDefaultBp: j['markupDefaultBp'] as int? ?? 0,
  );
}

class UsuarioCompanion {
  final int id;
  final String nombre;
  final bool activo;
  const UsuarioCompanion({required this.id, required this.nombre, this.activo = true});

  factory UsuarioCompanion.desdeJson(Map<String, dynamic> j) => UsuarioCompanion(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    activo: j['activo'] as bool? ?? true,
  );
}

/// Un encargue por apartado pendiente (`repositorio_encargues.dart`).
class EncargueCompanion {
  final int id;
  final String nombreCliente;
  final DateTime desde;

  /// Una línea de texto por producto apartado ("3 × Galletitas", "250 g Queso barra").
  final List<String> lineas;
  const EncargueCompanion({required this.id, required this.nombreCliente, required this.desde, required this.lineas});

  factory EncargueCompanion.desdeJson(Map<String, dynamic> j) => EncargueCompanion(
    id: j['id'] as int,
    nombreCliente: j['nombreCliente'] as String,
    desde: DateTime.fromMillisecondsSinceEpoch((j['desdeMs'] as num).toInt()),
    lineas: [for (final l in j['lineas'] as List) l as String],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombreCliente': nombreCliente,
    'desdeMs': desde.millisecondsSinceEpoch,
    'lineas': lineas,
  };
}

/// Una deuda anotada: un encargue que se entregó sin cobrar (`repositorio_encargues.dart`).
class DeudaCompanion {
  final int id;
  final String nombreCliente;
  final String detalle;
  final int montoCentavos;
  final DateTime desde;
  const DeudaCompanion({required this.id, required this.nombreCliente, required this.detalle, required this.montoCentavos, required this.desde});

  factory DeudaCompanion.desdeJson(Map<String, dynamic> j) => DeudaCompanion(
    id: j['id'] as int,
    nombreCliente: j['nombreCliente'] as String,
    detalle: j['detalle'] as String? ?? '',
    montoCentavos: (j['montoCentavos'] as num).toInt(),
    desde: DateTime.fromMillisecondsSinceEpoch((j['desdeMs'] as num).toInt()),
  );
}

/// Lo que se quiere apartar: unidades o, si es pesable, gramos (uno de los dos).
class ApartadoCompanion {
  final int productoId;
  final int? cantidad;
  final int? gramos;
  const ApartadoCompanion({required this.productoId, this.cantidad, this.gramos});

  Map<String, dynamic> toJson() => {'productoId': productoId, 'cantidad': ?cantidad, 'gramos': ?gramos};
}

class MedioDePagoCompanion {
  final int id;
  final String nombre;
  final bool esEfectivo;
  final bool activo;

  const MedioDePagoCompanion({
    required this.id,
    required this.nombre,
    required this.esEfectivo,
    required this.activo,
  });

  factory MedioDePagoCompanion.desdeJson(Map<String, dynamic> j) => MedioDePagoCompanion(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    esEfectivo: j['esEfectivo'] as bool,
    activo: j['activo'] as bool,
  );
}

/// Recargo de cigarrillos + paso de redondeo + producto de vuelto — las
/// reglas de negocio editables desde Configuración en la companion (El dueño,
/// 2026-09-19: "que se puedan modificar... desde el celular"). Espejo de
/// `ConfiguracionNegocio` (`lib/data/tables/configuracion_negocio.dart`),
/// sin `globalId`/`origenDispositivo`/`actualizadoEn`: son maquinaria de
/// sync, invisible para la companion.
class ConfiguracionNegocioCompanion {
  final int recargoPrimerAtadoCentavos;
  final int recargoAtadoAdicionalCentavos;
  final int recargoSueltoCentavos;
  final int pasoRedondeoCentavos;
  final int? productoVueltoId;

  const ConfiguracionNegocioCompanion({
    required this.recargoPrimerAtadoCentavos,
    required this.recargoAtadoAdicionalCentavos,
    required this.recargoSueltoCentavos,
    required this.pasoRedondeoCentavos,
    this.productoVueltoId,
  });

  factory ConfiguracionNegocioCompanion.desdeJson(Map<String, dynamic> j) => ConfiguracionNegocioCompanion(
    recargoPrimerAtadoCentavos: j['recargoPrimerAtadoCentavos'] as int,
    recargoAtadoAdicionalCentavos: j['recargoAtadoAdicionalCentavos'] as int,
    recargoSueltoCentavos: j['recargoSueltoCentavos'] as int,
    pasoRedondeoCentavos: j['pasoRedondeoCentavos'] as int,
    productoVueltoId: j['productoVueltoId'] as int?,
  );
}

class SesionCompanion {
  final bool abierta;

  /// Solo si `abierta`.
  final int? id;

  /// Solo si `abierta` — de acá sale, junto con [fechaUltimoArqueoIntermedio],
  /// si el arqueo obligatorio de 2hs ya venció (El dueño, 2026-09-13: "el
  /// bloqueo sincronizado con la app desktop"), con el mismo
  /// `necesitaArqueoIntermedio` de dominio que ya usa el escritorio.
  final DateTime? fechaApertura;

  /// Solo si `abierta` y ya se hizo al menos un arqueo intermedio en esta
  /// sesión — null significa "todavía ninguno", el conteo de 2hs arranca
  /// desde [fechaApertura] en ese caso.
  final DateTime? fechaUltimoArqueoIntermedio;

  /// Lo contado en el último arqueo del turno (El dueño, 2026-09-28: el cierre
  /// arranca precargado con eso). Null si todavía no hubo ninguno — y
  /// también si el que responde es una PC con una versión anterior que no
  /// manda estos campos: por eso `as int?` al parsear (TRAMPAS.md).
  final int? ultimoArqueoEfectivoCentavos;
  final int? ultimoArqueoMpCentavos;

  /// Solo si NO `abierta` y hubo algo que sugerir (turno entrante del mismo
  /// día) — ver `fondoInicialSugeridoCentavos` en `repositorio_cierre.dart`.
  final int? fondoInicialSugeridoCentavos;

  /// Solo si NO `abierta` — lo que va a quedar como lata inicial si se abre
  /// ahora (se arrastra sola, nunca se pregunta — Regla 10). Se muestra de
  /// antemano para que abrir caja no dé la sensación de "¿y la lata de
  /// cigarrillos?" (El dueño, 2026-09-10).
  final int? lataQueSeArrastraCentavos;

  /// Solo si `abierta` — quién la abrió (el servidor ya resuelve el join
  /// contra `usuarios`, mismo criterio que `nombreEmpleado` en
  /// `repositorio_historial.dart`) y desde qué dispositivo (`'android-…'` o
  /// el id de la PC), para poder avisar "Ya la abrió Fulano a las 9:15"
  /// cuando alguien más intenta abrir caja (El dueño, 2026-09-19: "aislar los
  /// usuarios para que no se pisen").
  final String? usuarioAbrioNombre;
  final String? origenDispositivo;

  const SesionCompanion({
    required this.abierta,
    this.id,
    this.fechaApertura,
    this.fechaUltimoArqueoIntermedio,
    this.ultimoArqueoEfectivoCentavos,
    this.ultimoArqueoMpCentavos,
    this.fondoInicialSugeridoCentavos,
    this.lataQueSeArrastraCentavos,
    this.usuarioAbrioNombre,
    this.origenDispositivo,
  });

  factory SesionCompanion.desdeJson(Map<String, dynamic> j) => SesionCompanion(
    abierta: j['abierta'] as bool,
    id: j['id'] as int?,
    fechaApertura: j['fechaApertura'] == null
        ? null
        : DateTime.parse(j['fechaApertura'] as String),
    fechaUltimoArqueoIntermedio: j['fechaUltimoArqueoIntermedio'] == null
        ? null
        : DateTime.parse(j['fechaUltimoArqueoIntermedio'] as String),
    ultimoArqueoEfectivoCentavos: j['ultimoArqueoEfectivoCentavos'] as int?,
    ultimoArqueoMpCentavos: j['ultimoArqueoMpCentavos'] as int?,
    fondoInicialSugeridoCentavos: j['fondoInicialSugeridoCentavos'] as int?,
    lataQueSeArrastraCentavos: j['lataQueSeArrastraCentavos'] as int?,
    usuarioAbrioNombre: j['usuarioAbrioNombre'] as String?,
    origenDispositivo: j['origenDispositivo'] as String?,
  );
}

/// Mismos tres valores que `MedioGasto` de `repositorio_gastos.dart` (los
/// nombres tienen que coincidir tal cual, `servidor_companion.dart` los
/// compara por `.name`) — un tipo propio en vez de importar el de `data/`
/// para no meter drift/database.dart en el build de Android, que la
/// companion nunca abre (mismo criterio que el resto de `lib/companion/`).
enum MedioGastoCompanion { cajonNormal, lata, mercadoPago }

/// Fragmento de body compartido por los cinco métodos que calculan/cobran
/// una venta (Regla 3) — `tipoDescuento == null` es "sin descuento", mismo
/// criterio que `servidor_companion.dart` del otro lado.
Map<String, dynamic> _descuentoAJson(
  TipoDescuento? tipoDescuento,
  int valorDescuento,
) => {
  if (tipoDescuento != null) 'tipoDescuento': tipoDescuento.name,
  if (tipoDescuento != null) 'valorDescuento': valorDescuento,
};

class ClienteCompanion implements ServicioCompanion {
  ClienteCompanion(this.conexion);

  final DatosConexion conexion;

  /// Compartido entre TODAS las instancias (no una por `ClienteCompanion`,
  /// que se crea de nuevo en cada pantalla) — `package:http`'s `get`/`post`/
  /// `delete` de nivel superior abren y cierran una conexión TCP por
  /// request; reusar un solo `Client` habilita keep-alive real contra la
  /// misma PC, que importa sobre todo cuando salen varias requests juntas
  /// (conteo de stock guardando muchos productos, búsquedas seguidas).
  /// Nunca se cierra explícitamente: vive tanto como el proceso de la app.
  static final http.Client _client = http.Client();

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'X-Companion-Token': conexion.token,
  };

  void _revisar(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String mensaje = 'Error inesperado (${r.statusCode})';
    try {
      mensaje =
          (jsonDecode(r.body) as Map<String, dynamic>)['error'] as String? ??
          mensaje;
    } catch (_) {
      // el cuerpo no era el JSON esperado — se deja el mensaje genérico
    }
    throw ErrorCompanion(r.statusCode, mensaje);
  }

  /// El mixto va por rutas propias a propósito: una PC sin actualizar ignoraría el monto en efectivo y le cobraría el
  /// total entero a la terminal. Con rutas nuevas, esa PC contesta 404 y no se cobra nada.
  void _revisarMixto(http.Response r, {required bool mixto}) {
    if (mixto && r.statusCode == 404) {
      throw const ErrorCompanion(404, 'Para cobrar mixto con la PC, actualizá la app de la PC.');
    }
    _revisar(r);
  }

  /// Sin token — solo confirma que hay algo escuchando en esa IP/puerto.
  /// Canjea el código de 6 números que muestra la PC (Configuración → Celular) por la llave de su servidor.
  static Future<DatosConexion> emparejarConCodigo(String ip, int puerto, String codigo, {http.Client? client}) async {
    final c = client ?? http.Client();
    final http.Response r;
    try {
      r = await c
          .post(
            Uri(scheme: 'http', host: ip, port: puerto, path: '/emparejar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'codigo': codigo.replaceAll(' ', '')}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const ErrorCompanion(0, 'No se pudo hablar con la PC. Revisá que siga prendida y en el mismo wifi.');
    }
    if (r.statusCode != 200) {
      String mensaje = 'La PC rechazó el código.';
      try {
        final j = jsonDecode(r.body);
        if (j is Map && j['error'] is String) mensaje = j['error'] as String;
      } catch (_) {}
      throw ErrorCompanion(r.statusCode, mensaje);
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return DatosConexion(ip: ip, puerto: (j['puerto'] as num?)?.toInt() ?? puerto, token: j['token'] as String);
  }

  static Future<bool> ping(String ip, int puerto) async {
    try {
      final r = await http
          .get(Uri(scheme: 'http', host: ip, port: puerto, path: '/ping'))
          .timeout(const Duration(seconds: 4));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<UsuarioCompanion>> usuarios() async {
    final r = await _client.get(conexion._url('/usuarios'), headers: _headers);
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(UsuarioCompanion.desdeJson)
        .toList();
  }

  // ─── Encargues por apartado ──────────────────────────────────────────

  @override
  Future<List<EncargueCompanion>> encargues() async {
    final r = await _client.get(conexion._url('/encargues'), headers: _headers);
    _revisar(r);
    return [for (final j in jsonDecode(r.body) as List) EncargueCompanion.desdeJson(Map<String, dynamic>.from(j as Map))];
  }

  @override
  Future<int> crearEncargue({
    required String nombreCliente,
    required List<ApartadoCompanion> lineas,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/encargues'),
      headers: _headers,
      body: jsonEncode({'nombreCliente': nombreCliente, 'usuarioId': usuarioId, 'lineas': [for (final l in lineas) l.toJson()]}),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  @override
  Future<void> cancelarEncargue(int id, {required int usuarioId}) async {
    final r = await _client.post(
      conexion._url('/encargues/$id/cancelar'),
      headers: _headers,
      body: jsonEncode({'usuarioId': usuarioId}),
    );
    _revisar(r);
  }

  @override
  Future<int> entregarEncargueADeuda(int id, {required int usuarioId}) async {
    final r = await _client.post(
      conexion._url('/encargues/$id/deuda'),
      headers: _headers,
      body: jsonEncode({'usuarioId': usuarioId}),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['totalCentavos'] as int;
  }

  @override
  Future<List<DeudaCompanion>> deudas() async {
    final r = await _client.get(conexion._url('/deudas'), headers: _headers);
    _revisar(r);
    return [for (final j in jsonDecode(r.body) as List) DeudaCompanion.desdeJson(Map<String, dynamic>.from(j as Map))];
  }

  @override
  Future<void> cobrarDeuda(int id, {required int usuarioId, required int sesionCajaId, required bool efectivo}) async {
    final r = await _client.post(
      conexion._url('/deudas/$id/cobrar'),
      headers: _headers,
      body: jsonEncode({'usuarioId': usuarioId, 'sesionCajaId': sesionCajaId, 'efectivo': efectivo}),
    );
    _revisar(r);
  }

  /// Lo apartado como líneas de venta, a los precios de hoy, para abrir el carrito.
  @override
  Future<List<LineaVenta>> lineasDeEncargue(int id) async {
    final r = await _client.get(conexion._url('/encargues/$id/lineas'), headers: _headers);
    _revisar(r);
    return [for (final j in jsonDecode(r.body) as List) lineaVentaDesdeJson(Map<String, dynamic>.from(j as Map))];
  }

  /// `versión+buildNumber` del lado de la PC — comparar tal cual contra
  /// `PackageInfo.fromPlatform()` del celular alcanza (misma `pubspec.yaml`
  /// para las dos plataformas, sistema de actualización 2026-09-07).
  Future<String> versionServidor() async {
    final r = await _client.get(
      conexion._url('/companion/version'),
      headers: _headers,
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return '${j['version']}+${j['buildNumber']}';
  }

  Future<List<int>> descargarApk() async {
    final r = await _client.get(
      conexion._url('/companion/apk'),
      headers: _headers,
    );
    _revisar(r);
    return r.bodyBytes;
  }

  @override
  Future<List<ProveedorCompanion>> proveedores() async {
    final r = await _client.get(
      conexion._url('/proveedores'),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ProveedorCompanion.desdeJson)
        .toList();
  }

  @override
  Future<List<CategoriaCompanion>> categorias() async {
    final r = await _client.get(
      conexion._url('/categorias'),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(CategoriaCompanion.desdeJson)
        .toList();
  }

  // ─── Configuración (El dueño, 2026-09-19: "que se puedan modificar las
  // reglas del negocio... desde el celular") ──────────────────────────────

  @override
  Future<ConfiguracionNegocioCompanion> configuracionNegocio() async {
    final r = await _client.get(conexion._url('/configuracion'), headers: _headers);
    _revisar(r);
    return ConfiguracionNegocioCompanion.desdeJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  @override
  Future<void> actualizarRecargoCigarrillos({
    required int primerAtadoCentavos,
    required int atadoAdicionalCentavos,
    required int sueltoCentavos,
  }) async {
    final r = await _client.put(
      conexion._url('/configuracion/recargo-cigarrillos'),
      headers: _headers,
      body: jsonEncode({
        'primerAtadoCentavos': primerAtadoCentavos,
        'atadoAdicionalCentavos': atadoAdicionalCentavos,
        'sueltoCentavos': sueltoCentavos,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> actualizarPasoRedondeo(int montoCentavos) async {
    final r = await _client.put(
      conexion._url('/configuracion/redondeo'),
      headers: _headers,
      body: jsonEncode({'montoCentavos': montoCentavos}),
    );
    _revisar(r);
  }

  @override
  Future<void> actualizarProductoVuelto(int? productoId) async {
    final r = await _client.put(
      conexion._url('/configuracion/producto-vuelto'),
      headers: _headers,
      body: jsonEncode({'productoId': productoId}),
    );
    _revisar(r);
  }

  @override
  Future<void> actualizarMarkupCategoria(int categoriaId, int markupBp) async {
    final r = await _client.put(
      conexion._url('/categorias/$categoriaId/markup'),
      headers: _headers,
      body: jsonEncode({'markupBp': markupBp}),
    );
    _revisar(r);
  }

  @override
  Future<List<MedioDePagoCompanion>> mediosDePago() async {
    final r = await _client.get(conexion._url('/medios-pago'), headers: _headers);
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(MedioDePagoCompanion.desdeJson)
        .toList();
  }

  @override
  Future<void> renombrarMedioPago(int id, String nombre) async {
    final r = await _client.put(
      conexion._url('/medios-pago/$id'),
      headers: _headers,
      body: jsonEncode({'nombre': nombre}),
    );
    _revisar(r);
  }

  @override
  Future<void> alternarActivoMedioPago(int id, bool activo) async {
    final r = await _client.put(
      conexion._url('/medios-pago/$id'),
      headers: _headers,
      body: jsonEncode({'activo': activo}),
    );
    _revisar(r);
  }

  @override
  Future<int> crearUsuarioNuevo(String nombre) async {
    final r = await _client.post(
      conexion._url('/usuarios'),
      headers: _headers,
      body: jsonEncode({'nombre': nombre}),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  @override
  Future<void> renombrarUsuarioExistente(int id, String nombre) async {
    final r = await _client.put(
      conexion._url('/usuarios/$id'),
      headers: _headers,
      body: jsonEncode({'nombre': nombre}),
    );
    _revisar(r);
  }

  @override
  Future<void> alternarActivoUsuarioExistente(int id, bool activo) async {
    final r = await _client.put(
      conexion._url('/usuarios/$id'),
      headers: _headers,
      body: jsonEncode({'activo': activo}),
    );
    _revisar(r);
  }

  @override
  Future<List<ProductoCompanion>> productos({
    String? busqueda,
    int? proveedorId,
    bool sinProveedor = false,
    bool sinCosto = false,
    bool sinCategoria = false,
    bool sinCodigoBarras = false,
  }) async {
    final r = await _client.get(
      conexion._url('/productos', {
        if (busqueda != null && busqueda.isNotEmpty) 'busqueda': busqueda,
        if (proveedorId != null) 'proveedorId': '$proveedorId',
        if (sinProveedor) 'sinProveedor': 'true',
        if (sinCosto) 'sinCosto': 'true',
        if (sinCategoria) 'sinCategoria': 'true',
        if (sinCodigoBarras) 'sinCodigoBarras': 'true',
      }),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ProductoCompanion.desdeJson)
        .toList();
  }

  /// Agotados o en negativo, de todos los proveedores juntos (El dueño,
  /// 2026-09-07: "revisar los productos sin stock... para ajustarlos") —
  /// mismo criterio que "Stock por proveedor" del escritorio
  /// (`productoAgotado`, Regla 8), calculado del lado del servidor.
  @override
  Future<List<ProductoCompanion>> productosSinStock() async {
    final r = await _client.get(
      conexion._url('/productos/sin-stock'),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ProductoCompanion.desdeJson)
        .toList();
  }

  /// Match exacto de código de barras (escáner) — `null` si no hay ningún
  /// producto con ese código, para que la pantalla ofrezca dar de alta en
  /// vez de mostrar un error.
  @override
  Future<ProductoCompanion?> porCodigoBarras(String codigo) async {
    final r = await _client.get(
      conexion._url('/productos/codigo/$codigo'),
      headers: _headers,
    );
    if (r.statusCode == 404) return null;
    _revisar(r);
    return ProductoCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<int> crearProducto({
    required String nombre,
    String? codigoBarras,
    int? categoriaId,
    int? proveedorId,
    required bool esPesable,
    int? precioCentavos,
    int? costoCentavos,
    int? precioPorKiloCentavos,
    int? costoPorKiloCentavos,
    int stock = 0,
    int? stockGramos,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/productos'),
      headers: _headers,
      body: jsonEncode({
        'nombre': nombre,
        'codigoBarras': ?codigoBarras,
        'categoriaId': ?categoriaId,
        'proveedorId': ?proveedorId,
        'esPesable': esPesable,
        'precioCentavos': ?precioCentavos,
        'costoCentavos': ?costoCentavos,
        'precioPorKiloCentavos': ?precioPorKiloCentavos,
        'costoPorKiloCentavos': ?costoPorKiloCentavos,
        'stock': stock,
        'stockGramos': ?stockGramos,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  @override
  Future<void> actualizarProducto(
    int id, {
    required String nombre,
    String? codigoBarras,
    int? categoriaId,
    int? proveedorId,
    required bool esPesable,
    int? precioCentavos,
    int? costoCentavos,
    int? precioPorKiloCentavos,
    int? costoPorKiloCentavos,
    required int stock,
    int? stockGramos,
    required bool activo,
    required int usuarioId,
  }) async {
    final r = await http.put(
      conexion._url('/productos/$id'),
      headers: _headers,
      body: jsonEncode({
        'nombre': nombre,
        'codigoBarras': ?codigoBarras,
        'categoriaId': ?categoriaId,
        'proveedorId': ?proveedorId,
        'esPesable': esPesable,
        'precioCentavos': ?precioCentavos,
        'costoCentavos': ?costoCentavos,
        'precioPorKiloCentavos': ?precioPorKiloCentavos,
        'costoPorKiloCentavos': ?costoPorKiloCentavos,
        'stock': stock,
        'stockGramos': ?stockGramos,
        'activo': activo,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> ajustarStock(
    int productoId, {
    required int stock,
    int? stockGramos,
    String? motivo,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/productos/$productoId/stock'),
      headers: _headers,
      body: jsonEncode({
        'stock': stock,
        'stockGramos': ?stockGramos,
        'motivo': ?motivo,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
  }

  // Editor masivo (El dueño, 2026-09-19: "editor masivo, ya sea de precios
  // costo stock etc etc") — ver `ServicioCompanion` para el porqué de cada
  // firma; acá solo empaqueta el pedido para el servidor
  // (`servidor_companion.dart`, sección "/productos/lote/*").
  @override
  Future<void> ajustarMontoEnLote({
    required List<int> productoIds,
    required CampoMonto campo,
    required TipoAjustePrecio tipo,
    required int valor,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/productos/lote/monto'),
      headers: _headers,
      body: jsonEncode({
        'productoIds': productoIds,
        'campo': campo.name,
        'tipo': tipo.name,
        'valor': valor,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> ajustarStockEnLote({
    required List<int> productoIds,
    required TipoAjusteStock tipo,
    required int valor,
    required int usuarioId,
    String motivo = 'Ajuste masivo',
  }) async {
    final r = await _client.post(
      conexion._url('/productos/lote/stock'),
      headers: _headers,
      body: jsonEncode({
        'productoIds': productoIds,
        'tipo': tipo.name,
        'valor': valor,
        'usuarioId': usuarioId,
        'motivo': motivo,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> asignarCategoriaEnLote({
    required List<int> productoIds,
    int? categoriaId,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/productos/lote/categoria'),
      headers: _headers,
      body: jsonEncode({
        'productoIds': productoIds,
        'categoriaId': categoriaId,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> asignarProveedorEnLote({
    required List<int> productoIds,
    int? proveedorId,
    required int usuarioId,
  }) async {
    final r = await _client.post(
      conexion._url('/productos/lote/proveedor'),
      headers: _headers,
      body: jsonEncode({
        'productoIds': productoIds,
        'proveedorId': proveedorId,
        'usuarioId': usuarioId,
      }),
    );
    _revisar(r);
  }

  @override
  Future<SesionCompanion> sesion() async {
    final r = await _client.get(conexion._url('/sesion'), headers: _headers);
    _revisar(r);
    return SesionCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  /// Vista previa del arqueo obligatorio de 2hs, sin guardar nada todavía
  /// (El dueño, 2026-09-13: "el bloqueo cada 2hs sincronizado con la app
  /// desktop") — mismo criterio que `calcularVenta`/`cobrarEfectivo`: se
  /// recalcula en vivo mientras se tipea, y recién `confirmarArqueoIntermedio`
  /// lo guarda de verdad.
  @override
  Future<EstadoArqueoIntermedioCompanion> calcularArqueoIntermedio({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) async {
    final r = await _client.post(
      conexion._url('/sesion/arqueo-intermedio/calcular'),
      headers: _headers,
      body: jsonEncode({
        'efectivoContadoCentavos': efectivoContadoCentavos,
        'mpContadoCentavos': ?mpContadoCentavos,
        'lataContadoCentavos': ?lataContadoCentavos,
      }),
    );
    _revisar(r);
    return EstadoArqueoIntermedioCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  /// Guarda el arqueo intermedio — los tres contados son obligatorios acá
  /// (a diferencia de `calcularArqueoIntermedio`), mismo criterio que el
  /// diálogo de escritorio: "es como el cierre, de punta a punta, en una
  /// sola confirmación".
  @override
  Future<void> confirmarArqueoIntermedio({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
  }) async {
    final r = await _client.post(
      conexion._url('/sesion/arqueo-intermedio/confirmar'),
      headers: _headers,
      body: jsonEncode({
        'usuarioId': usuarioId,
        'efectivoContadoCentavos': efectivoContadoCentavos,
        'mpContadoCentavos': mpContadoCentavos,
        'lataContadoCentavos': lataContadoCentavos,
      }),
    );
    _revisar(r);
  }

  /// Apertura de emergencia desde el celular — devuelve el id de la sesión
  /// nueva. El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" —
  /// si ya la abrieron desde la PC (o desde otro celular) entretanto, el
  /// servidor ya NO se une en silencio: da 409 con quién y a qué hora la
  /// abrió (`ErrorCompanion`, `_revisar` más abajo lo propaga tal cual).
  @override
  Future<int> abrirSesion({
    required int usuarioId,
    required int fondoInicialCentavos,
  }) async {
    final r = await _client.post(
      conexion._url('/sesion/abrir'),
      headers: _headers,
      body: jsonEncode({
        'usuarioId': usuarioId,
        'fondoInicialCentavos': fondoInicialCentavos,
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  /// Mismo molde que `calcularArqueoIntermedio`/`confirmarArqueoIntermedio`
  /// de arriba, pero para el cierre real (El dueño, 2026-09-19: "que deje
  /// cerrar caja desde el celular"). El desglose por proveedor viene
  /// resuelto (nombre, costo real, ganancia) — mismo `porProveedor` que ya
  /// trae `/caja/estado` (Regla 3, `_resumenDiaAJson` del servidor).
  @override
  Future<ResumenCierreCompanion> calcularCierre({
    required int efectivoContadoCentavos,
    int? mpContadoCentavos,
    int? lataContadoCentavos,
  }) async {
    final r = await _client.post(
      conexion._url('/sesion/cerrar/calcular'),
      headers: _headers,
      body: jsonEncode({
        'efectivoContadoCentavos': efectivoContadoCentavos,
        'mpContadoCentavos': ?mpContadoCentavos,
        'lataContadoCentavos': ?lataContadoCentavos,
      }),
    );
    _revisar(r);
    return ResumenCierreCompanion.desdeJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Guarda el cierre de verdad — los tres contados son obligatorios acá,
  /// mismo criterio que `confirmarArqueoIntermedio`.
  @override
  Future<void> confirmarCierre({
    required int usuarioId,
    required int efectivoContadoCentavos,
    required int mpContadoCentavos,
    required int lataContadoCentavos,
    String? nota,
  }) async {
    final r = await _client.post(
      conexion._url('/sesion/cerrar/confirmar'),
      headers: _headers,
      body: jsonEncode({
        'usuarioId': usuarioId,
        'efectivoContadoCentavos': efectivoContadoCentavos,
        'mpContadoCentavos': mpContadoCentavos,
        'lataContadoCentavos': lataContadoCentavos,
        'nota': ?nota,
      }),
    );
    _revisar(r);
  }

  /// Detalle completo de un cierre YA guardado (El dueño, 2026-09-19: rework
  /// de "Cierres" con el desglose por proveedor) — mismo shape que
  /// [calcularCierre], recalculado del lado del servidor con los conteos
  /// que ya quedaron guardados en esa sesión, nunca cacheado.
  @override
  Future<ResumenCierreCompanion> detalleCierre(int sesionId) async {
    final r = await _client.get(
      conexion._url('/sesiones/cerradas/$sesionId/detalle'),
      headers: _headers,
    );
    _revisar(r);
    return ResumenCierreCompanion.desdeJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// "¿Cómo vamos?" en cualquier momento del día, sin contar nada a mano
  /// (El dueño, 2026-09-07: "un botón de arqueo también... sin tener que
  /// contar a mano las ventas del día") — efectivo/MP esperados (mismas
  /// fórmulas del cierre real) más el resumen por medio/proveedor, para la
  /// sesión de hoy que sigue abierta. Nunca la diferencia de arqueo: esa
  /// necesita plata contada, que es justo lo que este botón evita.
  @override
  Future<EstadoCajaCompanion> estadoCaja() async {
    final r = await _client.get(
      conexion._url('/caja/estado'),
      headers: _headers,
    );
    _revisar(r);
    return EstadoCajaCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<Map<int, int>> saldosProveedores() async {
    final r = await _client.get(conexion._url('/proveedores/saldos'), headers: _headers);
    _revisar(r);
    return {
      for (final e in (jsonDecode(r.body) as Map<String, dynamic>).entries)
        int.parse(e.key): (e.value as num).toInt(),
    };
  }

  @override
  Future<int> pagarProveedor({
    required int proveedorId,
    required int usuarioId,
    required int montoCentavos,
    required String origen,
    int? sesionCajaId,
    String? nota,
  }) async {
    final r = await _client.post(
      conexion._url('/proveedores/$proveedorId/pagos'),
      headers: _headers,
      body: jsonEncode({
        'usuarioId': usuarioId,
        'montoCentavos': montoCentavos,
        'origen': origen,
        'sesionCajaId': ?sesionCajaId,
        'nota': ?nota,
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  @override
  Future<int> registrarGasto({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) async {
    final r = await _client.post(
      conexion._url('/gastos'),
      headers: _headers,
      body: jsonEncode({
        'sesionCajaId': sesionCajaId,
        'usuarioId': usuarioId,
        'montoCentavos': montoCentavos,
        'medio': medio.name,
        'motivo': ?motivo,
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  /// "Ingreso rápido" (El dueño, 2026-09-13) — espejo exacto de `registrarGasto`,
  /// mismas tres cajas (`MedioGastoCompanion`, reusado).
  @override
  Future<int> registrarIngreso({
    required int sesionCajaId,
    required int usuarioId,
    required int montoCentavos,
    required MedioGastoCompanion medio,
    String? motivo,
  }) async {
    final r = await _client.post(
      conexion._url('/ingresos'),
      headers: _headers,
      body: jsonEncode({
        'sesionCajaId': sesionCajaId,
        'usuarioId': usuarioId,
        'montoCentavos': montoCentavos,
        'medio': medio.name,
        'motivo': ?motivo,
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as int;
  }

  // ─── Vender (El dueño, 2026-09-07) ──────────────────────────────────────
  //
  // El carrito es una `List<LineaVenta>` — el mismo tipo del dominio, ver
  // `domain/venta_json.dart` — armada en el celular con lo que devuelve
  // `buscarVenta`. Nada de esto recalcula nada: el servidor corre las
  // mismas fórmulas que `VentaControlador` (Regla 3).

  /// Busca con la misma lógica que el campo único de la pantalla de venta
  /// del escritorio (stock filtrado — Regla 8 —, "200 queso" para
  /// pesables). `gramos` no nulo significa que el texto pedía esa cantidad
  /// de un pesable — el llamador lo usa para armar la línea al tocar un
  /// resultado, sin volver a parsear el texto acá (un solo lugar, el
  /// servidor).
  /// [exigirStock] en `false` para la carga histórica (El dueño: "no
  /// descuentan stock... para saber ganancias") — un producto vendido en su
  /// momento puede estar en 0 hoy por cualquier otro motivo.
  @override
  Future<({int? gramos, List<ProductoCompanion> resultados})> buscarVenta(
    String texto, {
    bool exigirStock = true,
  }) async {
    final r = await _client.get(
      conexion._url('/ventas/buscar', {
        'texto': texto,
        if (!exigirStock) 'exigirStock': 'false',
      }),
      headers: _headers,
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      gramos: j['gramos'] as int?,
      resultados: (j['resultados'] as List)
          .cast<Map<String, dynamic>>()
          .map(ProductoCompanion.desdeJson)
          .toList(),
    );
  }

  /// `medio` es `'efectivo'` o `'virtual'` — sin Mixto en esta primera
  /// versión (decisión de el dueño, 2026-09-07). [tipoDescuento]/[valorDescuento]:
  /// Regla 17 generalizada, mismo criterio que el escritorio — `null` o
  /// `valorDescuento == 0` es "sin descuento".
  @override
  Future<ResultadoTotalVenta> calcularVenta({
    required List<LineaVenta> lineas,
    required String medio,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
  }) async {
    final r = await _client.post(
      conexion._url('/ventas/calcular'),
      headers: _headers,
      body: jsonEncode({
        'lineas': [for (final l in lineas) lineaVentaAJson(l)],
        'medio': medio,
        ..._descuentoAJson(tipoDescuento, valorDescuento),
      }),
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ResultadoTotalVenta(
      subtotalCentavos: j['subtotalCentavos'] as int,
      recargoCigarrillosCentavos: j['recargoCigarrillosCentavos'] as int,
      descuentoCentavos: j['descuentoCentavos'] as int,
      redondeoCentavos: j['redondeoCentavos'] as int,
      totalCentavos: j['totalCentavos'] as int,
    );
  }

  /// Efectivo directo, sin pasar por la terminal — QR/Débito usan el ciclo
  /// de tres pasos de abajo.
  @override
  Future<({int ventaId, int totalCentavos})> cobrarEfectivo({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
  }) async {
    final r = await _client.post(
      conexion._url('/ventas/cobrar'),
      headers: _headers,
      body: jsonEncode({
        'lineas': [for (final l in lineas) lineaVentaAJson(l)],
        'medio': 'efectivo',
        'sesionCajaId': sesionCajaId,
        'usuarioId': usuarioId,
        ..._descuentoAJson(tipoDescuento, valorDescuento),
        'encargueId': ?encargueId,
        'claveCobro': ?claveCobro,
      }),
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      ventaId: j['ventaId'] as int,
      totalCentavos: j['totalCentavos'] as int,
    );
  }

  /// "Cobrar a mano" (El dueño, 2026-09-07: "para cargar las ventas de hoy y
  /// seguir cargando mientras tanto" — no bloquearse si el posnet tarda o
  /// falla) — graba la venta directo, sin pasar por el ciclo de Point,
  /// pero conservando el canal elegido (mismo criterio que
  /// `VentaControlador.cobrarActual()` desde el diálogo de escritorio: la
  /// venta sigue siendo QR/Débito para el dato informativo del medio,
  /// aunque el pago no se haya verificado por la terminal).
  @override
  Future<({int ventaId, int totalCentavos})> cobrarVirtualAMano({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    required String canal,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
    int? montoEfectivoMixtoCentavos,
  }) async {
    final mixto = montoEfectivoMixtoCentavos != null;
    final r = await _client.post(
      conexion._url(mixto ? '/ventas/mixto/cobrar' : '/ventas/cobrar'),
      headers: _headers,
      body: jsonEncode({
        'lineas': [for (final l in lineas) lineaVentaAJson(l)],
        'medio': mixto ? 'mixto' : 'virtual',
        'canal': canal,
        'sesionCajaId': sesionCajaId,
        'usuarioId': usuarioId,
        ..._descuentoAJson(tipoDescuento, valorDescuento),
        'encargueId': ?encargueId,
        'claveCobro': ?claveCobro,
        'montoEfectivoMixtoCentavos': ?montoEfectivoMixtoCentavos,
      }),
    );
    _revisarMixto(r, mixto: mixto);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      ventaId: j['ventaId'] as int,
      totalCentavos: j['totalCentavos'] as int,
    );
  }

  /// Crea la orden en la terminal Point (`canal`: `'qr'` | `'debit_card'`) —
  /// mismo primer paso que `VentaControlador.iniciarCobroPosnet`. El
  /// celular hace el polling después, contra [consultarEstadoPosnet].
  @override
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})>
  iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? montoEfectivoMixtoCentavos,
  }) async {
    final mixto = montoEfectivoMixtoCentavos != null;
    final r = await _client.post(
      conexion._url(mixto ? '/ventas/mixto/posnet/iniciar' : '/ventas/posnet/iniciar'),
      headers: _headers,
      body: jsonEncode({
        'lineas': [for (final l in lineas) lineaVentaAJson(l)],
        'canal': canal,
        'sesionCajaId': sesionCajaId,
        ..._descuentoAJson(tipoDescuento, valorDescuento),
        'montoEfectivoMixtoCentavos': ?montoEfectivoMixtoCentavos,
      }),
    );
    _revisarMixto(r, mixto: mixto);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      ordenPendienteId: j['ordenPendienteId'] as int,
      ordenIdMp: j['ordenIdMp'] as String,
      totalCentavos: j['totalCentavos'] as int,
    );
  }

  @override
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) async {
    final r = await _client.get(
      conexion._url('/ventas/posnet/estado/$ordenIdMp'),
      headers: _headers,
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return resultadoDesdeRespuesta(j['estado'] as String?, enTerminal: j['enTerminal'] == true);
  }

  /// El pago se aprobó: recién acá se graba la venta real (mismo criterio
  /// que `VentaControlador.confirmarCobroPosnetAprobado`).
  /// [tipoDescuento]/[valorDescuento] tienen que ser los MISMOS que se
  /// mandaron a `iniciarCobroPosnet` — esta ruta recalcula el total desde
  /// cero, no reusa el de la orden ya creada.
  @override
  Future<({int ventaId, int totalCentavos})> confirmarCobroPosnet({
    required int ordenPendienteId,
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    int? montoEfectivoMixtoCentavos,
  }) async {
    final mixto = montoEfectivoMixtoCentavos != null;
    final r = await _client.post(
      conexion._url(mixto ? '/ventas/mixto/posnet/confirmar' : '/ventas/posnet/confirmar'),
      headers: _headers,
      body: jsonEncode({
        'ordenPendienteId': ordenPendienteId,
        'lineas': [for (final l in lineas) lineaVentaAJson(l)],
        'canal': canal,
        'sesionCajaId': sesionCajaId,
        'usuarioId': usuarioId,
        ..._descuentoAJson(tipoDescuento, valorDescuento),
        'encargueId': ?encargueId,
        'montoEfectivoMixtoCentavos': ?montoEfectivoMixtoCentavos,
      }),
    );
    _revisarMixto(r, mixto: mixto);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      ventaId: j['ventaId'] as int,
      totalCentavos: j['totalCentavos'] as int,
    );
  }

  @override
  Future<void> resolverCobroPosnetNoAprobado({
    required int ordenPendienteId,
    required String estado,
  }) async {
    final r = await _client.post(
      conexion._url('/ventas/posnet/no-aprobado'),
      headers: _headers,
      body: jsonEncode({
        'ordenPendienteId': ordenPendienteId,
        'estado': estado,
      }),
    );
    _revisar(r);
  }

  @override
  Future<void> cancelarCobroPosnet({
    required int ordenPendienteId,
    String? ordenIdMp,
  }) async {
    final r = await _client.post(
      conexion._url('/ventas/posnet/cancelar'),
      headers: _headers,
      body: jsonEncode({
        'ordenPendienteId': ordenPendienteId,
        'ordenIdMp': ?ordenIdMp,
      }),
    );
    _revisar(r);
  }

  Future<void> imprimirTicket(int ventaId) async {
    final r = await _client.post(
      conexion._url('/ventas/$ventaId/imprimir'),
      headers: _headers,
    );
    _revisar(r);
  }

  // ─── Carga histórica (El dueño, 2026-09-07) ─────────────────────────────
  //
  // Nada se graba hasta [guardarDiaHistorico] — el celular junta las
  // ventas del día en memoria (`VentaHistoricaPendienteCompanion`), igual
  // que `CargaHistoricaControlador` en el escritorio, y las manda todas
  // juntas en un solo POST.

  /// Un día completo, en una sola transacción del lado del servidor
  /// (`cargarDiaHistoricoDesdeVentas`) — devuelve el id de la sesión
  /// creada.
  @override
  Future<int> guardarDiaHistorico({
    required DateTime fecha,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) async {
    final r = await _client.post(
      conexion._url('/historico/dia'),
      headers: _headers,
      body: jsonEncode({
        'fecha': fecha.toIso8601String(),
        'usuarioId': usuarioId,
        'ventas': [for (final v in ventas) v._aJson()],
      }),
    );
    _revisar(r);
    return (jsonDecode(r.body) as Map<String, dynamic>)['sesionId'] as int;
  }

  // Ver y editar días ya cargados (El dueño, 2026-09-07: "dejame verlos y
  // editarlos porque le erré y lo cerré sin completarlo").

  @override
  Future<List<DiaHistoricoCompanion>> diasHistoricos() async {
    final r = await _client.get(
      conexion._url('/historico/dias'),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(DiaHistoricoCompanion.desdeJson)
        .toList();
  }

  @override
  Future<List<VentaHistoricaResumenCompanion>> ventasDeDiaHistorico(
    int sesionId,
  ) async {
    final r = await _client.get(
      conexion._url('/historico/dias/$sesionId'),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(VentaHistoricaResumenCompanion.desdeJson)
        .toList();
  }

  /// Vendido por medio de pago y por proveedor (con la separación teórica,
  /// Regla 5) de un día ya cargado — El dueño, 2026-09-07: "necesitaría un
  /// resumen... así que al entrar a un día".
  @override
  Future<ResumenDiaHistoricoCompanion> resumenDiaHistorico(int sesionId) async {
    final r = await _client.get(
      conexion._url('/historico/dias/$sesionId/resumen'),
      headers: _headers,
    );
    _revisar(r);
    return ResumenDiaHistoricoCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  /// Agrega más ventas a un día ya cargado, sin crear una sesión nueva —
  /// El dueño: "le erré y lo cerré sin completarlo", seguir cargando en vez
  /// de tener que borrar todo.
  @override
  Future<void> agregarVentasADiaHistorico({
    required int sesionId,
    required int usuarioId,
    required List<VentaHistoricaPendienteCompanion> ventas,
  }) async {
    final r = await _client.post(
      conexion._url('/historico/dias/$sesionId/agregar'),
      headers: _headers,
      body: jsonEncode({
        'usuarioId': usuarioId,
        'ventas': [for (final v in ventas) v._aJson()],
      }),
    );
    _revisar(r);
  }

  /// Borra UNA venta de un día ya cargado — nunca toca stock (nunca lo
  /// tocó al cargarla).
  @override
  Future<void> eliminarVentaHistorica({
    required int sesionId,
    required int ventaId,
    required int usuarioId,
  }) async {
    final r = await _client.delete(
      conexion._url('/historico/dias/$sesionId/ventas/$ventaId'),
      headers: _headers,
      body: jsonEncode({'usuarioId': usuarioId}),
    );
    _revisar(r);
  }

  /// Borra el día completo — el escape hatch cuando conviene empezar de
  /// cero antes que corregir venta por venta.
  @override
  Future<void> eliminarDiaHistorico(int sesionId) async {
    final r = await _client.delete(
      conexion._url('/historico/dias/$sesionId'),
      headers: _headers,
    );
    _revisar(r);
  }

  /// Historial de ventas, filtrable (El dueño, 2026-09-07: "tipo mercado
  /// pago... para un control manual en caso de desconfiar de los
  /// números"). [filtroMedio] null trae todas.
  @override
  Future<List<VentaDelHistorialCompanion>> historialDeVentas({
    required DateTime desde,
    required DateTime hasta,
    MedioVentaHistorialCompanion? filtroMedio,
  }) async {
    final query = {
      'desde': desde.toIso8601String(),
      'hasta': hasta.toIso8601String(),
      if (filtroMedio != null) 'medio': filtroMedio.name,
    };
    final r = await _client.get(
      conexion._url('/historial/ventas', query),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(VentaDelHistorialCompanion.desdeJson)
        .toList();
  }

  /// Cierres reales (El dueño, 2026-09-13: "quiero la pantalla nueva de
  /// cierres con caché offline") — excluye días de carga histórica del
  /// lado del servidor, acá solo llega lo que es un arqueo de verdad.
  @override
  Future<List<SesionCerradaCompanion>> sesionesCerradas({int limite = 30}) async {
    final r = await _client.get(
      conexion._url('/sesiones/cerradas', {'limite': '$limite'}),
      headers: _headers,
    );
    _revisar(r);
    return (jsonDecode(r.body) as List)
        .cast<Map<String, dynamic>>()
        .map(SesionCerradaCompanion.desdeJson)
        .toList();
  }

  /// Desglose de una venta (El dueño, 2026-09-13: "poder ver un desglose de
  /// la venta") — mismo `Ticket` que arma la impresión, del lado del
  /// servidor (Regla 3).
  @override
  Future<DetalleVentaCompanion> detalleVenta(int ventaId) async {
    final r = await _client.get(
      conexion._url('/ventas/$ventaId/detalle'),
      headers: _headers,
    );
    _revisar(r);
    return DetalleVentaCompanion.desdeJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  /// Anula una venta ya cobrada (El dueño, 2026-09-13: eliminar una venta
  /// desde el celular) — el servidor rechaza con [ErrorCompanion] si la
  /// sesión de esa venta ya está cerrada, o si ya estaba anulada.
  @override
  Future<void> anularVenta({
    required int ventaId,
    required int usuarioId,
    required String motivo,
  }) async {
    final r = await _client.post(
      conexion._url('/ventas/$ventaId/anular'),
      headers: _headers,
      body: jsonEncode({'usuarioId': usuarioId, 'motivo': motivo}),
    );
    _revisar(r);
  }

  /// Una PC vieja no tiene esta ruta (404): ahí no se ofrece la devolución, y se hace desde la app de Mercado Pago.
  @override
  Future<CobroPoint?> cobroPointDeVenta(int ventaId) async {
    try {
      final r = await _client.get(conexion._url('/ventas/$ventaId/cobro-point'), headers: _headers);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map<String, dynamic> && j['cobro'] is Map<String, dynamic> ? CobroPoint.desdeJson(j['cobro'] as Map<String, dynamic>) : null;
    } catch (e, st) {
      // Sin la orden no se ofrece devolver; si no es solo falta de red, queda anotado.
      unawaited(registrarSiNoEsDeRed('Pedir a la PC el cobro de una venta', e, st));
      return null;
    }
  }

  // ─── Sincronización (fase 2, "companion sin depender del escritorio") ──
  //
  // Las filas viajan tal cual las arma `repositorio_sincronizacion.dart` del
  // lado de la PC (columnas SQL crudas, snake_case) y se aplican tal cual
  // con la misma función del lado del celular — Regla 3, ningún parseo
  // propio acá.

  /// Filas de [tabla] nuevas o cambiadas desde el cursor [desde] — ver
  /// `lib/data/repositorio_sincronizacion.dart::cambiosDesde` para el
  /// significado exacto de "cursor". Devuelve también el cursor más alto
  /// entre esas filas, para que quien llama sepa qué guardar como el
  /// próximo `desde`.
  Future<({List<Map<String, dynamic>> filas, int cursor})> cambiosDesde({
    required String tabla,
    required int desde,
  }) async {
    final r = await _client.get(
      conexion._url('/sync/cambios', {'tabla': tabla, 'desde': '$desde'}),
      headers: _headers,
    );
    _revisar(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      filas: (j['filas'] as List).cast<Map<String, dynamic>>(),
      cursor: j['cursor'] as int,
    );
  }

  /// Manda [filas] de [tabla] a la PC para que las aplique con el mismo
  /// mecanismo de "gana el cambio más reciente" — ver
  /// `repositorio_sincronizacion.dart::aplicarCambios`.
  Future<void> enviarCambios({
    required String tabla,
    required List<Map<String, dynamic>> filas,
  }) async {
    final r = await _client.post(
      conexion._url('/sync/cambios'),
      headers: _headers,
      body: jsonEncode({'tabla': tabla, 'filas': filas}),
    );
    _revisar(r);
  }
}

/// 'efectivo' | 'qr' | 'debitCard' | 'mixto' — mismos valores que
/// `MedioVentaHistorial` (`repositorio_historial_ventas.dart`).
enum MedioVentaHistorialCompanion { efectivo, qr, debitCard, mixto, creditCard }

class VentaDelHistorialCompanion {
  final int ventaId;

  /// Número de venta global; null en las ventas anteriores a la v48 o contra una PC que todavía no lo manda.
  final String? numero;
  final DateTime fecha;
  final int totalCentavos;
  final MedioVentaHistorialCompanion medio;
  final String detalle;
  final bool anulada;

  /// Si se puede eliminar esta venta — condicionado a que la sesión de
  /// caja de esa venta siga abierta (El dueño, 2026-09-13).
  final bool sesionAbierta;

  String get etiqueta => numero ?? '#$ventaId';

  const VentaDelHistorialCompanion({
    required this.ventaId,
    this.numero,
    required this.fecha,
    required this.totalCentavos,
    required this.medio,
    required this.detalle,
    required this.anulada,
    required this.sesionAbierta,
  });

  /// `anulada`/`sesionAbierta` son `as bool?` (no `as bool`) a propósito:
  /// un servidor de escritorio todavía sin reiniciar con este código no los
  /// manda — sin el `?`, un celular ya actualizado contra una PC vieja
  /// crasheaba acá ("type 'Null' is not a subtype of type 'bool'") en vez
  /// de mostrar el historial igual. Mismo criterio que
  /// `tipoDescuento`/`_calcularResultado` (compatibilidad con clientes
  /// viejos, ver los tests del servidor): default `false` — "no se puede
  /// eliminar todavía" es lo seguro mientras el escritorio no se actualizó.
  factory VentaDelHistorialCompanion.desdeJson(Map<String, dynamic> j) =>
      VentaDelHistorialCompanion(
        ventaId: j['ventaId'] as int,
        numero: j['numero'] as String?,
        fecha: DateTime.parse(j['fecha'] as String),
        totalCentavos: j['totalCentavos'] as int,
        medio: j['tarjeta'] == 'credito'
            ? MedioVentaHistorialCompanion.creditCard
            : MedioVentaHistorialCompanion.values.where((m) => m.name == j['medio']).firstOrNull ?? MedioVentaHistorialCompanion.qr,
        detalle: j['detalle'] as String,
        anulada: j['anulada'] as bool? ?? false,
        sesionAbierta: j['sesionAbierta'] as bool? ?? false,
      );
}

/// Un cierre real (sesión de caja cerrada, con su arqueo) — El dueño,
/// 2026-09-13: "quiero la pantalla nueva de cierres con caché offline".
/// Los `*Centavos` de cada caja son nullable porque, en teoría, una
/// sesión ya cerrada siempre los tiene completos — pero un cierre viejo de
/// antes de alguna columna, o una fila incompleta, no debería tirar abajo
/// toda la pantalla por un solo campo faltante.
class SesionCerradaCompanion {
  final int sesionId;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final String nombreEmpleado;
  final int totalVendidoCentavos;
  final int? efectivoContadoCentavos;
  final int? efectivoEsperadoCentavos;
  final int? diferenciaCentavos;
  final int? mpContadoCentavos;
  final int? mpEsperadoCentavos;
  final int? mpDiferenciaCentavos;
  final int? lataContadoCentavos;
  final int? lataFinalCentavos;
  final int? lataDiferenciaCentavos;

  const SesionCerradaCompanion({
    required this.sesionId,
    required this.fechaApertura,
    this.fechaCierre,
    required this.nombreEmpleado,
    required this.totalVendidoCentavos,
    this.efectivoContadoCentavos,
    this.efectivoEsperadoCentavos,
    this.diferenciaCentavos,
    this.mpContadoCentavos,
    this.mpEsperadoCentavos,
    this.mpDiferenciaCentavos,
    this.lataContadoCentavos,
    this.lataFinalCentavos,
    this.lataDiferenciaCentavos,
  });

  factory SesionCerradaCompanion.desdeJson(Map<String, dynamic> j) =>
      SesionCerradaCompanion(
        sesionId: j['sesionId'] as int,
        fechaApertura: DateTime.parse(j['fechaApertura'] as String),
        fechaCierre: j['fechaCierre'] == null
            ? null
            : DateTime.parse(j['fechaCierre'] as String),
        nombreEmpleado: j['nombreEmpleado'] as String,
        totalVendidoCentavos: j['totalVendidoCentavos'] as int,
        efectivoContadoCentavos: j['efectivoContadoCentavos'] as int?,
        efectivoEsperadoCentavos: j['efectivoEsperadoCentavos'] as int?,
        diferenciaCentavos: j['diferenciaCentavos'] as int?,
        mpContadoCentavos: j['mpContadoCentavos'] as int?,
        mpEsperadoCentavos: j['mpEsperadoCentavos'] as int?,
        mpDiferenciaCentavos: j['mpDiferenciaCentavos'] as int?,
        lataContadoCentavos: j['lataContadoCentavos'] as int?,
        lataFinalCentavos: j['lataFinalCentavos'] as int?,
        lataDiferenciaCentavos: j['lataDiferenciaCentavos'] as int?,
      );

  /// El camino inverso de `desdeJson` — hace falta para el caché offline
  /// (`cache_cierres.dart`): lo que llegó por HTTP se vuelve a guardar tal
  /// cual, como texto, en `shared_preferences`.
  Map<String, dynamic> aJson() => {
    'sesionId': sesionId,
    'fechaApertura': fechaApertura.toIso8601String(),
    'fechaCierre': ?fechaCierre?.toIso8601String(),
    'nombreEmpleado': nombreEmpleado,
    'totalVendidoCentavos': totalVendidoCentavos,
    'efectivoContadoCentavos': ?efectivoContadoCentavos,
    'efectivoEsperadoCentavos': ?efectivoEsperadoCentavos,
    'diferenciaCentavos': ?diferenciaCentavos,
    'mpContadoCentavos': ?mpContadoCentavos,
    'mpEsperadoCentavos': ?mpEsperadoCentavos,
    'mpDiferenciaCentavos': ?mpDiferenciaCentavos,
    'lataContadoCentavos': ?lataContadoCentavos,
    'lataFinalCentavos': ?lataFinalCentavos,
    'lataDiferenciaCentavos': ?lataDiferenciaCentavos,
  };
}

/// Una línea del desglose — mismo dato que `LineaTicket` (dominio,
/// `domain/ticket.dart`), copiado acá porque el celular nunca importa
/// dominio de escritorio (todo le llega por HTTP/JSON, `cliente_companion.dart`).
class LineaTicketCompanion {
  final String nombreProducto;
  final int cantidad;
  final int? gramos;
  final int subtotalCentavos;

  const LineaTicketCompanion({
    required this.nombreProducto,
    required this.cantidad,
    this.gramos,
    required this.subtotalCentavos,
  });

  factory LineaTicketCompanion.desdeJson(Map<String, dynamic> j) =>
      LineaTicketCompanion(
        nombreProducto: j['nombreProducto'] as String,
        cantidad: j['cantidad'] as int,
        gramos: j['gramos'] as int?,
        subtotalCentavos: j['subtotalCentavos'] as int,
      );
}

/// Desglose completo de una venta (El dueño, 2026-09-13: "poder ver un
/// desglose de la venta") — mismo `Ticket` que arma la impresión, del lado
/// del servidor.
class DetalleVentaCompanion {
  final DateTime fecha;
  final String vendedor;
  final List<LineaTicketCompanion> lineas;
  final int recargoCigarrillosCentavos;
  final int descuentoCentavos;
  final int redondeoCentavos;
  final int totalCentavos;

  const DetalleVentaCompanion({
    required this.fecha,
    required this.vendedor,
    required this.lineas,
    required this.recargoCigarrillosCentavos,
    required this.descuentoCentavos,
    required this.redondeoCentavos,
    required this.totalCentavos,
  });

  int get subtotalCentavos =>
      lineas.fold(0, (acc, l) => acc + l.subtotalCentavos);

  factory DetalleVentaCompanion.desdeJson(Map<String, dynamic> j) =>
      DetalleVentaCompanion(
        fecha: DateTime.parse(j['fecha'] as String),
        vendedor: j['vendedor'] as String,
        lineas: (j['lineas'] as List)
            .cast<Map<String, dynamic>>()
            .map(LineaTicketCompanion.desdeJson)
            .toList(),
        recargoCigarrillosCentavos: j['recargoCigarrillosCentavos'] as int,
        descuentoCentavos: j['descuentoCentavos'] as int,
        redondeoCentavos: j['redondeoCentavos'] as int,
        totalCentavos: j['totalCentavos'] as int,
      );
}

/// Vista previa del arqueo obligatorio de 2hs (El dueño, 2026-09-13) —
/// `mpDiferenciaCentavos`/`lataDiferenciaCentavos` son null hasta que se
/// tipeó el contado correspondiente, mismo criterio que el escritorio
/// (`ResumenCierre`).
class EstadoArqueoIntermedioCompanion {
  final int efectivoEsperadoCentavos;
  final int diferenciaCentavos;
  final int mpEsperadoCentavos;
  final int? mpDiferenciaCentavos;
  final int lataEsperadoCentavos;
  final int? lataDiferenciaCentavos;

  const EstadoArqueoIntermedioCompanion({
    required this.efectivoEsperadoCentavos,
    required this.diferenciaCentavos,
    required this.mpEsperadoCentavos,
    this.mpDiferenciaCentavos,
    required this.lataEsperadoCentavos,
    this.lataDiferenciaCentavos,
  });

  factory EstadoArqueoIntermedioCompanion.desdeJson(Map<String, dynamic> j) =>
      EstadoArqueoIntermedioCompanion(
        efectivoEsperadoCentavos: j['efectivoEsperadoCentavos'] as int,
        diferenciaCentavos: j['diferenciaCentavos'] as int,
        mpEsperadoCentavos: j['mpEsperadoCentavos'] as int,
        mpDiferenciaCentavos: j['mpDiferenciaCentavos'] as int?,
        lataEsperadoCentavos: j['lataEsperadoCentavos'] as int,
        lataDiferenciaCentavos: j['lataDiferenciaCentavos'] as int?,
      );
}

class DiaHistoricoCompanion {
  final int sesionId;
  final DateTime fecha;
  final int totalCentavos;
  final int cantidadVentas;

  const DiaHistoricoCompanion({
    required this.sesionId,
    required this.fecha,
    required this.totalCentavos,
    required this.cantidadVentas,
  });

  factory DiaHistoricoCompanion.desdeJson(Map<String, dynamic> j) =>
      DiaHistoricoCompanion(
        sesionId: j['sesionId'] as int,
        fecha: DateTime.parse(j['fecha'] as String),
        totalCentavos: j['totalCentavos'] as int,
        cantidadVentas: j['cantidadVentas'] as int,
      );
}

/// `medioResumen` es `'efectivo'` | `'virtual'` | `'mixto'`.
class VentaHistoricaResumenCompanion {
  final int ventaId;
  final int totalCentavos;
  final String medioResumen;
  final String detalle;

  const VentaHistoricaResumenCompanion({
    required this.ventaId,
    required this.totalCentavos,
    required this.medioResumen,
    required this.detalle,
  });

  factory VentaHistoricaResumenCompanion.desdeJson(Map<String, dynamic> j) =>
      VentaHistoricaResumenCompanion(
        ventaId: j['ventaId'] as int,
        totalCentavos: j['totalCentavos'] as int,
        medioResumen: j['medioResumen'] as String,
        detalle: j['detalle'] as String,
      );
}

/// Ver `ProductoSinDatos` en `repositorio_carga_historica.dart`.
class ProductoSinDatosCompanion {
  final int? productoId;
  final String nombreProducto;
  final int vendidoCentavos;
  final bool sinProveedor;
  final bool sinCosto;

  const ProductoSinDatosCompanion({
    required this.productoId,
    required this.nombreProducto,
    required this.vendidoCentavos,
    required this.sinProveedor,
    required this.sinCosto,
  });

  factory ProductoSinDatosCompanion.desdeJson(Map<String, dynamic> j) =>
      ProductoSinDatosCompanion(
        productoId: j['productoId'] as int?,
        nombreProducto: j['nombreProducto'] as String,
        vendidoCentavos: j['vendidoCentavos'] as int,
        sinProveedor: j['sinProveedor'] as bool,
        sinCosto: j['sinCosto'] as bool,
      );
}

class ResumenProveedorDiaCompanion {
  final int proveedorId;
  final String nombreProveedor;
  final int vendidoCentavos;

  /// = separación teórica (Regla 5: la reposición es el costo real).
  final int costoRealCentavos;
  final int gananciaCentavos;

  const ResumenProveedorDiaCompanion({
    required this.proveedorId,
    required this.nombreProveedor,
    required this.vendidoCentavos,
    required this.costoRealCentavos,
    required this.gananciaCentavos,
  });

  factory ResumenProveedorDiaCompanion.desdeJson(Map<String, dynamic> j) =>
      ResumenProveedorDiaCompanion(
        proveedorId: j['proveedorId'] as int,
        nombreProveedor: j['nombreProveedor'] as String,
        vendidoCentavos: j['vendidoCentavos'] as int,
        costoRealCentavos: j['costoRealCentavos'] as int,
        gananciaCentavos: j['gananciaCentavos'] as int,
      );
}

class ResumenDiaHistoricoCompanion {
  final int totalCentavos;
  final int efectivoCentavos;
  final int mercadoPagoCentavos;

  /// Precio de lista de los cigarrillos — lo que hay que separar a la lata
  /// para Distribuidora de Cigarrillos (Regla 6). Nunca entra en `porProveedor`.
  final int cigarrillosListaCentavos;
  final int vendidoSinCostoCentavos;
  final List<ProductoSinDatosCompanion> productosSinDatos;
  final List<ResumenProveedorDiaCompanion> porProveedor;

  const ResumenDiaHistoricoCompanion({
    required this.totalCentavos,
    required this.efectivoCentavos,
    required this.mercadoPagoCentavos,
    required this.cigarrillosListaCentavos,
    required this.vendidoSinCostoCentavos,
    required this.productosSinDatos,
    required this.porProveedor,
  });

  factory ResumenDiaHistoricoCompanion.desdeJson(Map<String, dynamic> j) =>
      ResumenDiaHistoricoCompanion(
        totalCentavos: j['totalCentavos'] as int,
        efectivoCentavos: j['efectivoCentavos'] as int,
        mercadoPagoCentavos: j['mercadoPagoCentavos'] as int,
        cigarrillosListaCentavos: j['cigarrillosListaCentavos'] as int,
        vendidoSinCostoCentavos: j['vendidoSinCostoCentavos'] as int,
        productosSinDatos: (j['productosSinDatos'] as List)
            .cast<Map<String, dynamic>>()
            .map(ProductoSinDatosCompanion.desdeJson)
            .toList(),
        porProveedor: (j['porProveedor'] as List)
            .cast<Map<String, dynamic>>()
            .map(ResumenProveedorDiaCompanion.desdeJson)
            .toList(),
      );
}

/// Resumen completo de un cierre real, calculado en vivo (todavía sin
/// guardar) — `ClienteCompanion.calcularCierre`/`confirmarCierre`, el dueño
/// 2026-09-19: "que deje cerrar caja desde el celular". Combina lo que
/// antes solo veía el escritorio (`ResumenCierre`, `repositorio_cierre.dart`)
/// con el mismo desglose por proveedor de `ResumenDiaHistoricoCompanion`
/// (Regla 3: un solo `_resumenDiaAJson` del lado del servidor alimenta a
/// los dos).
class ResumenCierreCompanion {
  final int efectivoEsperadoCentavos;
  final int diferenciaCentavos;
  final int mpEsperadoCentavos;
  final int? mpDiferenciaCentavos;
  final int lataFinalCentavos;
  final int? lataDiferenciaCentavos;
  final int separadoCentavos;
  final int pendienteCentavos;
  final bool esSeparacionParcial;
  final int redondeoAcumuladoCentavos;
  final int? reservaDiariaFijosCentavos;
  final int totalCentavos;
  final int efectivoCentavos;
  final int mercadoPagoCentavos;
  final int cigarrillosListaCentavos;
  final int vendidoSinCostoCentavos;
  final List<ProductoSinDatosCompanion> productosSinDatos;
  final List<ResumenProveedorDiaCompanion> porProveedor;

  /// Solo vienen de `GET /sesiones/cerradas/<id>/detalle` (un cierre ya
  /// guardado) — la vista previa en vivo de `calcularCierre` no los manda:
  /// esa pantalla ya tiene los tres contados en sus propios campos de
  /// texto, no hace falta que el servidor se los devuelva.
  final String? nota;
  final int? efectivoContadoCentavos;
  final int? mpContadoCentavos;
  final int? lataContadoCentavos;

  const ResumenCierreCompanion({
    required this.efectivoEsperadoCentavos,
    required this.diferenciaCentavos,
    required this.mpEsperadoCentavos,
    this.mpDiferenciaCentavos,
    required this.lataFinalCentavos,
    this.lataDiferenciaCentavos,
    required this.separadoCentavos,
    required this.pendienteCentavos,
    required this.esSeparacionParcial,
    required this.redondeoAcumuladoCentavos,
    this.reservaDiariaFijosCentavos,
    required this.totalCentavos,
    required this.efectivoCentavos,
    required this.mercadoPagoCentavos,
    required this.cigarrillosListaCentavos,
    required this.vendidoSinCostoCentavos,
    required this.productosSinDatos,
    required this.porProveedor,
    this.nota,
    this.efectivoContadoCentavos,
    this.mpContadoCentavos,
    this.lataContadoCentavos,
  });

  factory ResumenCierreCompanion.desdeJson(Map<String, dynamic> j) =>
      ResumenCierreCompanion(
        efectivoEsperadoCentavos: j['efectivoEsperadoCentavos'] as int,
        diferenciaCentavos: j['diferenciaCentavos'] as int,
        mpEsperadoCentavos: j['mpEsperadoCentavos'] as int,
        mpDiferenciaCentavos: j['mpDiferenciaCentavos'] as int?,
        lataFinalCentavos: j['lataFinalCentavos'] as int,
        lataDiferenciaCentavos: j['lataDiferenciaCentavos'] as int?,
        separadoCentavos: j['separadoCentavos'] as int,
        pendienteCentavos: j['pendienteCentavos'] as int,
        esSeparacionParcial: j['esSeparacionParcial'] as bool,
        redondeoAcumuladoCentavos: j['redondeoAcumuladoCentavos'] as int,
        reservaDiariaFijosCentavos: j['reservaDiariaFijosCentavos'] as int?,
        totalCentavos: j['totalCentavos'] as int,
        efectivoCentavos: j['efectivoCentavos'] as int,
        mercadoPagoCentavos: j['mercadoPagoCentavos'] as int,
        cigarrillosListaCentavos: j['cigarrillosListaCentavos'] as int,
        vendidoSinCostoCentavos: j['vendidoSinCostoCentavos'] as int,
        productosSinDatos: (j['productosSinDatos'] as List)
            .cast<Map<String, dynamic>>()
            .map(ProductoSinDatosCompanion.desdeJson)
            .toList(),
        porProveedor: (j['porProveedor'] as List)
            .cast<Map<String, dynamic>>()
            .map(ResumenProveedorDiaCompanion.desdeJson)
            .toList(),
        nota: j['nota'] as String?,
        efectivoContadoCentavos: j['efectivoContadoCentavos'] as int?,
        mpContadoCentavos: j['mpContadoCentavos'] as int?,
        lataContadoCentavos: j['lataContadoCentavos'] as int?,
      );
}

/// "Arqueo" en vivo de la sesión de hoy — ver `ClienteCompanion.estadoCaja`.
class EstadoCajaCompanion {
  final int sesionId;
  final DateTime fechaApertura;
  final int efectivoEsperadoCentavos;
  final int mpEsperadoCentavos;

  /// Ya incluido dentro de [efectivoEsperadoCentavos] — se muestra aparte
  /// en pantalla para que no se confunda con un descuadre (Regla 2, mismo
  /// motivo que el cierre real del escritorio).
  final int redondeoAcumuladoCentavos;

  /// La lata que se arrastra de ANTES de hoy — su valor de hoy recién se
  /// sabe al cerrar de verdad (Regla 10, separación depende de lo contado).
  final int lataInicialCentavos;

  final int cantidadVentas;
  final ResumenDiaHistoricoCompanion resumen;

  const EstadoCajaCompanion({
    required this.sesionId,
    required this.fechaApertura,
    required this.efectivoEsperadoCentavos,
    required this.mpEsperadoCentavos,
    required this.redondeoAcumuladoCentavos,
    required this.lataInicialCentavos,
    required this.cantidadVentas,
    required this.resumen,
  });

  factory EstadoCajaCompanion.desdeJson(Map<String, dynamic> j) =>
      EstadoCajaCompanion(
        sesionId: j['sesionId'] as int,
        fechaApertura: DateTime.parse(j['fechaApertura'] as String),
        efectivoEsperadoCentavos: j['efectivoEsperadoCentavos'] as int,
        mpEsperadoCentavos: j['mpEsperadoCentavos'] as int,
        // `as int?` (no `as int`) a propósito: si la PC todavía corre un
        // build del escritorio anterior a estos dos campos (2026-09-10),
        // el servidor no los manda y el cast estricto tiraba
        // "type 'Null' is not a subtype of type 'int'" — crasheaba el
        // Arqueo entero por un campo que ni se estaba mostrando mal, solo
        // ausente. `?? 0` degrada sin romper hasta que la PC se actualice.
        redondeoAcumuladoCentavos:
            (j['redondeoAcumuladoCentavos'] as int?) ?? 0,
        lataInicialCentavos: (j['lataInicialCentavos'] as int?) ?? 0,
        cantidadVentas: j['cantidadVentas'] as int,
        // El mismo objeto trae `resumen` "aplanado" en las mismas claves que
        // `ResumenDiaHistoricoCompanion.desdeJson` ya sabe leer (Regla 3: un
        // solo parser, no uno nuevo por endpoint que devuelve la misma forma).
        resumen: ResumenDiaHistoricoCompanion.desdeJson(j),
      );
}

/// Una venta ya armada (carrito + medio elegido), esperando a que se guarde
/// el día completo — `medio` es `'efectivo'` | `'virtual'` | `'mixto'`.
class VentaHistoricaPendienteCompanion {
  final List<LineaVenta> lineas;
  final String medio;

  /// Solo con `medio == 'mixto'`.
  final int? montoEfectivoMixtoCentavos;

  /// El total ya calculado (con recargo de cigarrillos y redondeo, Regla
  /// 6/5) al momento de confirmar esta venta en `_ArmadorDeVenta` — solo
  /// para mostrarlo en el resumen mientras se siguen cargando más ventas
  /// del día (El dueño, 2026-09-07: "revisa que la apk no agrega los
  /// recargos automáticos"). El servidor vuelve a calcularlo de cero al
  /// guardar (`POST /historico/dia`), este campo nunca viaja — es solo
  /// para la UI.
  final int? totalCentavos;

  const VentaHistoricaPendienteCompanion({
    required this.lineas,
    required this.medio,
    this.montoEfectivoMixtoCentavos,
    this.totalCentavos,
  });

  int get subtotalCentavos =>
      lineas.fold(0, (acc, l) => acc + l.subtotalCentavos);

  /// Lo que corresponde mostrar en pantalla — el total real si ya se
  /// calculó, el subtotal crudo como aproximación si no.
  int get totalParaMostrar => totalCentavos ?? subtotalCentavos;

  Map<String, dynamic> _aJson() => {
    'lineas': [for (final l in lineas) lineaVentaAJson(l)],
    'medio': medio,
    'montoEfectivoMixtoCentavos': ?montoEfectivoMixtoCentavos,
  };
}
