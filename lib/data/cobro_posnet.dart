// Cobro por terminal Point vía Orders API (Fase 12) — POST /v1/orders para
// crear la orden, GET /v1/orders/{id} para consultar el resultado por
// polling. Mismo patrón que `impresion_posnet.dart` (única otra acción de
// la app que llama a un servidor externo): un fallo acá nunca debe tocar
// la venta — el llamador decide qué hacer con el error, esta función solo
// garantiza que sea un error claro.
//
// Body real verificado contra la documentación de Mercado Pago (no un
// supuesto): `type: "point"`, `transactions.payments[0].amount` (string
// decimal, nunca centavos), `config.point.terminal_id` +
// `print_on_terminal: "no_ticket"` (imprimir es una acción aparte de esta
// app, no le pedimos a la terminal que imprima su propio ticket),
// `config.payment_method` (`medioDePagoOrden`: `qr` | `debit_card` | `credit_card` en 1 pago).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/cobro_posnet.dart' show duracionIso8601, medioDePagoOrden, vencimientoOrdenCobroPosnet;
import '../domain/dinero.dart';

class CobroPosnetException implements Exception {
  final String mensaje;

  /// `true` cuando NO se sabe si Mercado Pago llegó a hacer lo pedido (se cortó la red, venció el plazo, respondió un 5xx).
  /// Distinto de un rechazo (4xx), donde Mercado Pago dijo que no: ahí la orden no existe. Quien crea una orden usa esto para
  /// decidir si reintenta con la MISMA clave de idempotencia (incierto) o si da el intento por fallido (rechazo).
  final bool incierto;

  const CobroPosnetException(this.mensaje, {this.incierto = false});

  @override
  String toString() => mensaje;
}

/// Cuánto se espera una respuesta de Mercado Pago antes de darla por perdida: sin tope, una conexión colgada dejaba el diálogo
/// de cobro girando para siempre. No es `const` solo para que los tests puedan bajarlo; el código de la app no lo toca.
Duration plazoLlamadaMercadoPago = const Duration(seconds: 25);

/// Un id de orden de Mercado Pago (alfanumérico, con guiones o guion bajo). Se valida antes de armar una dirección con él: el id
/// puede venir del celular, y un `..%2F` colado cambiaría a qué endpoint de la API se le manda el token de la PC.
final _idOrdenValido = RegExp(r'^[\w-]{1,64}$');

String _idOrdenSeguro(String ordenIdMp) {
  if (!_idOrdenValido.hasMatch(ordenIdMp)) throw const CobroPosnetException('El id de la orden de Mercado Pago no es válido.');
  return ordenIdMp;
}

/// Corre una llamada HTTP con tope de espera y traduce los cortes de red a [CobroPosnetException] (`incierto`): los diálogos de
/// cobro solo entienden esa excepción, y una `SocketException` suelta los dejaba colgados sin decir nada.
Future<T> _conRed<T>(Future<T> Function() llamada) async {
  try {
    return await llamada().timeout(plazoLlamadaMercadoPago);
  } on TimeoutException {
    throw const CobroPosnetException('Mercado Pago no respondió a tiempo. Revisá la conexión a internet.', incierto: true);
  } on SocketException {
    throw const CobroPosnetException('No hay conexión con Mercado Pago. Revisá la conexión a internet.', incierto: true);
  } on HttpException {
    throw const CobroPosnetException('La conexión con Mercado Pago se cortó. Probá de nuevo.', incierto: true);
  } on TlsException {
    throw const CobroPosnetException('No se pudo abrir una conexión segura con Mercado Pago. Revisá la fecha y hora de la PC.', incierto: true);
  } on http.ClientException {
    throw const CobroPosnetException('La conexión con Mercado Pago se cortó. Probá de nuevo.', incierto: true);
  }
}

class OrdenCobroCreada {
  final String ordenIdMp;
  final String estado;
  const OrdenCobroCreada({required this.ordenIdMp, required this.estado});
}

Future<OrdenCobroCreada> crearOrdenCobro({
  required String accessToken,
  required String terminalId,
  required String externalReference,
  required String idempotencyKey,
  required int montoCentavos,
  required String canal,
  http.Client? client,
}) async {
  final cliente = client ?? http.Client();
  try {
    final respuesta = await _conRed(() => cliente.post(
      Uri.parse('https://api.mercadopago.com/v1/orders'),
      headers: {
        'Content-Type': 'application/json',
        'X-Idempotency-Key': idempotencyKey,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'type': 'point',
        'external_reference': externalReference,
        // Vence sola si nadie la paga (etapa A): la terminal deja de esperar y la app ve `expired` en vez de quedarse sin saber.
        'expiration_time': duracionIso8601(vencimientoOrdenCobroPosnet),
        'transactions': {
          'payments': [
            {'amount': formatearParaMercadoPago(montoCentavos)},
          ],
        },
        'config': {
          'point': {
            'terminal_id': terminalId,
            'print_on_terminal': 'no_ticket',
          },
          'payment_method': medioDePagoOrden(canal),
        },
      }),
    ));

    final cuerpo = _decodificarONull(respuesta.body);
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw CobroPosnetException(
        'Mercado Pago Orders API (${respuesta.statusCode}): ${_mensajeDeError(cuerpo, respuesta.body)}',
        // Un 5xx no dice si la orden se creó; un 4xx sí: no se creó.
        incierto: respuesta.statusCode >= 500,
      );
    }
    final id = cuerpo?['id']?.toString();
    final estado = cuerpo?['status']?.toString();
    if (id == null || estado == null) {
      throw CobroPosnetException(
        'Mercado Pago Orders API: respuesta sin id/status (${respuesta.body})',
        incierto: true, // contestó 2xx pero sin id: la orden pudo haberse creado
      );
    }
    return OrdenCobroCreada(ordenIdMp: id, estado: estado);
  } finally {
    if (client == null) cliente.close();
  }
}

/// Devuelve el `status` actual de la orden (tabla real en
/// `lib/domain/cobro_posnet.dart`, `clasificarEstadoOrden`).
Future<String> consultarOrden({
  required String accessToken,
  required String ordenIdMp,
  http.Client? client,
}) async {
  final cliente = client ?? http.Client();
  try {
    final id = _idOrdenSeguro(ordenIdMp);
    final respuesta = await _conRed(() => cliente.get(
      Uri.parse('https://api.mercadopago.com/v1/orders/${Uri.encodeComponent(id)}'),
      headers: {'Authorization': 'Bearer $accessToken'},
    ));

    final cuerpo = _decodificarONull(respuesta.body);
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw CobroPosnetException(
        'Mercado Pago Orders API (${respuesta.statusCode}): ${_mensajeDeError(cuerpo, respuesta.body)}',
      );
    }
    final estado = cuerpo?['status']?.toString();
    if (estado == null) {
      throw CobroPosnetException(
        'Mercado Pago Orders API: respuesta sin status (${respuesta.body})',
      );
    }
    return estado;
  } finally {
    if (client == null) cliente.close();
  }
}

/// Cancela la orden del lado de Mercado Pago — indispensable para que la
/// terminal deje de esperar el pago (El dueño: "cuando cancelo el QR no
/// cancela el dispositivo"). Sin esto, "Cancelar" en la app solo actualizaba
/// nuestra propia fila; el posnet seguía mostrando "esperando pago" hasta
/// que la orden expirara sola del lado de MP.
///
/// Solo funciona con `status=created` — verificado contra el posnet real de
/// El dueño, no un supuesto: una vez que la orden llega a la terminal
/// (`status=at_terminal`, que pasa casi al instante de crearla) la API
/// responde `409 cannot_cancel_order` y **no hay vuelta**, hay que cancelar
/// desde el propio dispositivo. Por eso este error se traduce a un mensaje
/// de negocio en vez de mostrar el JSON crudo — es el caso esperado, no uno
/// excepcional, y el llamador (`dialogo_cobro_posnet.dart`) lo usa para
/// decirle a el dueño que vaya a la terminal en vez de reintentar por acá.
Future<void> cancelarOrdenCobro({
  required String accessToken,
  required String ordenIdMp,
  http.Client? client,
}) async {
  final cliente = client ?? http.Client();
  try {
    final id = _idOrdenSeguro(ordenIdMp);
    final respuesta = await _conRed(() => cliente.post(
      Uri.parse('https://api.mercadopago.com/v1/orders/${Uri.encodeComponent(id)}/cancel'),
      headers: {
        'Content-Type': 'application/json',
        'X-Idempotency-Key': _claveIdempotencia(),
        'Authorization': 'Bearer $accessToken',
      },
    ));

    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      final cuerpo = _decodificarONull(respuesta.body);
      if (_codigoDeError(cuerpo) == 'cannot_cancel_order') {
        throw const CobroPosnetException(
          'La terminal ya recibió la orden: a partir de ese momento, Mercado Pago no permite cancelarla por API.',
        );
      }
      throw CobroPosnetException(
        'Mercado Pago Orders API (${respuesta.statusCode}): ${_mensajeDeError(cuerpo, respuesta.body)}',
      );
    }
  } finally {
    if (client == null) cliente.close();
  }
}

String _claveIdempotencia() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Map<String, dynamic>? _decodificarONull(String body) {
  try {
    final valor = jsonDecode(body);
    return valor is Map<String, dynamic> ? valor : null;
  } catch (_) {
    return null;
  }
}

/// MP usa dos formas de error según el endpoint: `{"message": "..."}` (la
/// que ya se esperaba acá) y `{"errors": [{"code", "message", ...}]}` (la
/// que realmente devolvió al validar `terminal_id` y al rechazar un
/// cancel — antes de esto, ninguna de las dos se entendía y se mostraba el
/// JSON crudo entero).
String _mensajeDeError(Map<String, dynamic>? cuerpo, String bodyCrudo) {
  final mensaje = cuerpo?['message'];
  if (mensaje != null) return mensaje.toString();
  final primerError = _primerError(cuerpo);
  return primerError?['message']?.toString() ?? bodyCrudo;
}

String? _codigoDeError(Map<String, dynamic>? cuerpo) {
  return _primerError(cuerpo)?['code']?.toString();
}

Map<String, dynamic>? _primerError(Map<String, dynamic>? cuerpo) {
  final errores = cuerpo?['errors'];
  if (errores is List &&
      errores.isNotEmpty &&
      errores.first is Map<String, dynamic>) {
    return errores.first as Map<String, dynamic>;
  }
  return null;
}

/// Por dónde sale el cobro a la terminal: directo contra Mercado Pago con el access token cargado en la PC
/// ([PasarelaPointDirecta], lo de siempre) o a través del servidor de Nodo Sur con la cuenta conectada del negocio
/// (`servicios/pasarela_point_nube.dart`). Quien cobra (la pantalla de venta, el servidor del celular, el celular sin PC) no
/// tiene que saber cuál es: pide una [PasarelaPoint] y usa estas tres operaciones.
abstract class PasarelaPoint {
  Future<OrdenCobroCreada> crear({
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  });

  /// El `status` actual de la orden (se clasifica con `clasificarEstadoOrden`).
  Future<String> consultar(String ordenIdMp);

  /// Lanza [CobroPosnetException] con el mensaje de negocio si la terminal ya recibió la orden.
  Future<void> cancelar(String ordenIdMp);
}

/// El camino de siempre: access token y terminal cargados en la PC, llamando a Mercado Pago directamente.
class PasarelaPointDirecta implements PasarelaPoint {
  const PasarelaPointDirecta({required this.accessToken, required this.terminalId, this.client});
  final String accessToken;
  final String terminalId;
  final http.Client? client;

  @override
  Future<OrdenCobroCreada> crear({
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  }) => crearOrdenCobro(
    accessToken: accessToken,
    terminalId: terminalId,
    externalReference: externalReference,
    idempotencyKey: idempotencyKey,
    montoCentavos: montoCentavos,
    canal: canal,
    client: client,
  );

  @override
  Future<String> consultar(String ordenIdMp) => consultarOrden(accessToken: accessToken, ordenIdMp: ordenIdMp, client: client);

  @override
  Future<void> cancelar(String ordenIdMp) => cancelarOrdenCobro(accessToken: accessToken, ordenIdMp: ordenIdMp, client: client);
}
