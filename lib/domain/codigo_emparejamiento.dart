// Código de emparejamiento de 6 números (El dueño, 2026-10-03: "que empareje por un código numérico de una sola vez"):
// la PC muestra el código, el celular lo tipea y recibe la llave del servidor de la PC. Reemplaza al QR con la llave a la
// vista. Puro: el reloj y el azar llegan de afuera.
//
// Por qué alcanza con 6 números: dura 5 minutos, sirve una sola vez, y a los 5 intentos fallidos se anula (con 10^6
// combinaciones, adivinarlo en 5 intentos es 1 en 200.000). Además el pedido solo llega desde el wifi del local.

import 'dart:math';

enum ResultadoCanje { ok, incorrecto, vencido, sinCodigo, anulado }

class GestorCodigoEmparejamiento {
  GestorCodigoEmparejamiento({DateTime Function()? reloj, Random? azar})
    : _reloj = reloj ?? DateTime.now,
      _azar = azar ?? Random.secure();

  static const vigencia = Duration(minutes: 5);
  static const maxFallos = 5;

  final DateTime Function() _reloj;
  final Random _azar;

  String? _codigo;
  DateTime? _vence;
  int _fallos = 0;

  /// El código vigente, o null si no hay (nunca se generó, se usó, venció o se anuló).
  String? get codigo => _vigente ? _codigo : null;

  /// Cuánto le queda al código vigente (cero si no hay).
  Duration get restante => _vigente ? _vence!.difference(_reloj()) : Duration.zero;

  bool get _vigente => _codigo != null && _reloj().isBefore(_vence!);

  /// Un código nuevo: el anterior deja de valer.
  String generar() {
    _codigo = _azar.nextInt(1000000).toString().padLeft(6, '0');
    _vence = _reloj().add(vigencia);
    _fallos = 0;
    return _codigo!;
  }

  void anular() => _codigo = null;

  ResultadoCanje canjear(String intento) {
    if (_codigo == null) return ResultadoCanje.sinCodigo;
    if (!_vigente) {
      _codigo = null;
      return ResultadoCanje.vencido;
    }
    if (intento.trim() == _codigo) {
      _codigo = null; // de un solo uso
      return ResultadoCanje.ok;
    }
    _fallos++;
    if (_fallos >= maxFallos) {
      _codigo = null;
      return ResultadoCanje.anulado;
    }
    return ResultadoCanje.incorrecto;
  }
}
