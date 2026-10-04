// Cobrar con la terminal Point a través del servidor de Nodo Sur (El dueño, 2026-10-02: que el QR y el débito anden sin que la PC
// esté prendida). El negocio conecta SU cuenta de Mercado Pago una vez en horsepos.com/negocio; el token queda en el servidor y la
// PC y el celular le piden la orden al sitio con su cuenta vinculada. Nada de esto toca lo que ya anda: una PC con access token
// cargado sigue cobrando directo (`elegirPasarelaPoint`).

import '../data/cobro_posnet.dart';
import 'cuenta_nube.dart';

class PasarelaPointNube implements PasarelaPoint {
  const PasarelaPointNube({required this.cliente, required this.token});
  final ClienteNube cliente;
  final String token;

  /// Los errores del servidor se vuelven `CobroPosnetException` (lo único que entienden los diálogos de cobro).
  Future<T> _traducir<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ErrorNube catch (e) {
      throw CobroPosnetException(
        e.pideVincularDeNuevo ? 'Este dispositivo ya no está vinculado a la cuenta. Volvé a vincularlo para cobrar con la terminal.' : e.mensaje,
        incierto: _noSabeSiSeHizo(e),
      );
    }
  }

  /// Sin red, o el servidor/Mercado Pago no contestó (5xx, plazo vencido): no se sabe si la orden se creó. `mp_rechazo` (un 4xx de
  /// Mercado Pago, que el servidor devuelve como 502) sí es un "no" definitivo.
  static bool _noSabeSiSeHizo(ErrorNube e) => e.esDeRed || (e.estado != null && e.estado! >= 500 && e.codigo != 'mp_rechazo');

  @override
  Future<OrdenCobroCreada> crear({
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  }) => _traducir(() async {
    final r = await cliente.crearOrdenPoint(token, externalReference: externalReference, idempotencyKey: idempotencyKey, montoCentavos: montoCentavos, canal: canal);
    return OrdenCobroCreada(ordenIdMp: r.id, estado: r.estado);
  });

  @override
  Future<String> consultar(String ordenIdMp) => _traducir(() => cliente.consultarOrdenPoint(token, ordenIdMp));

  @override
  Future<void> cancelar(String ordenIdMp) async {
    try {
      await _traducir(() => cliente.cancelarOrdenPoint(token, ordenIdMp));
    } on CobroPosnetException catch (e) {
      // Una orden que ya llegó a la terminal no se cancela por API: es el caso esperado, con el mismo mensaje de siempre.
      if (e.mensaje.contains('cannot_cancel_order')) {
        throw const CobroPosnetException('La terminal ya recibió la orden: a partir de ese momento, Mercado Pago no permite cancelarla por API.');
      }
      rethrow;
    }
  }
}

/// Elige por dónde cobrar. Con access token Y terminal cargados en este equipo (la PC de siempre) se cobra directo, sin cambiar
/// nada de lo que ya anda. Si no, y el dispositivo está vinculado a la cuenta, se cobra por el servidor siempre que el negocio
/// tenga Mercado Pago conectado y una terminal elegida para su sucursal. Si no, se dice qué falta.
Future<PasarelaPoint> elegirPasarelaPoint({
  String? accessToken,
  String? terminalId,
  required AlmacenCuenta? almacen,
  required ClienteNube? cliente,
  PasarelaPoint Function(String accessToken, String terminalId)? directa,
  // Consultar y cancelar una orden ya creada no necesitan la terminal: alcanza con el token (como siempre).
  bool soloToken = false,
  // Interruptor de prueba: ignora el access token local y cobra siempre por el servidor.
  bool forzarNube = false,
  String mensajeSinCuenta =
      'Configurá el access token y la terminal de cobro en Configuración → Impresión antes de cobrar por acá, '
      'o vinculá este dispositivo a tu cuenta y conectá Mercado Pago en horsepos.com/negocio.',
}) async {
  if (!forzarNube && accessToken != null && (terminalId != null || soloToken)) {
    final terminal = terminalId ?? '';
    return directa != null ? directa(accessToken, terminal) : PasarelaPointDirecta(accessToken: accessToken, terminalId: terminal);
  }
  final cuenta = await almacen?.leer();
  if (cuenta == null || cliente == null) throw CobroPosnetException(mensajeSinCuenta);
  final EstadoMp estado;
  try {
    estado = await cliente.estadoMp(cuenta.token);
  } on ErrorNube catch (e) {
    throw CobroPosnetException(e.pideVincularDeNuevo ? 'Este dispositivo ya no está vinculado a la cuenta. Volvé a vincularlo para cobrar con la terminal.' : e.mensaje);
  }
  if (estado.necesitaReconectar) {
    throw const CobroPosnetException('La conexión con Mercado Pago se cortó: el dueño tiene que reconectarla en horsepos.com/negocio.');
  }
  if (!estado.conectado) {
    throw const CobroPosnetException('Mercado Pago todavía no está conectado: el dueño lo conecta en horsepos.com/negocio.');
  }
  if (!estado.terminalElegida) {
    throw const CobroPosnetException('Esta sucursal no tiene una terminal elegida: el dueño la elige en horsepos.com/negocio.');
  }
  return PasarelaPointNube(cliente: cliente, token: cuenta.token);
}
