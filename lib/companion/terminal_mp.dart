// Si la sucursal tiene una terminal Point elegida (en horsepos.com/negocio), para la pantalla de cobro del celular: sin terminal
// el QR sale en la pantalla y débito/crédito no se ofrecen (`domain/cobro_qr.dart`). Se pregunta al sitio y se recuerda unos
// minutos: elegir un medio de pago no puede esperar a la red.

import 'demo/demo.dart';
import 'sync_nube_companion.dart';

const _vida = Duration(minutes: 5);
({bool? hay, DateTime en})? _memoria;

/// true/false si se pudo saber; null sin cuenta, sin internet o en la demo (la pantalla queda como siempre).
Future<bool?> hayTerminalEnLaSucursal() async {
  if (modoDemo) return null;
  final m = _memoria;
  if (m != null && DateTime.now().difference(m.en) < _vida) return m.hay;
  bool? hay;
  try {
    final sync = await syncNubeDelCelular();
    final cuenta = await sync.almacen.leer();
    hay = cuenta == null ? null : (await sync.cliente.estadoMp(cuenta.token)).terminalElegida;
  } catch (_) {
    hay = null;
  }
  _memoria = (hay: hay, en: DateTime.now());
  return hay;
}

/// Para tests, o al cambiar la terminal: la próxima consulta va al sitio.
void olvidarTerminalEnLaSucursal() => _memoria = null;
