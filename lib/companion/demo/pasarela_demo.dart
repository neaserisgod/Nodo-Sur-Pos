// El cobro por Mercado Pago de la demo (horsepos.com/demo/): la demo no tiene cuenta ni terminal, así que la "terminal" aprueba
// sola a los pocos segundos. Se ve el mismo camino que en el negocio de verdad (esperando el pago → cobrado) sin mandar nada a
// Mercado Pago.

import '../../data/cobro_posnet.dart';

class PasarelaPointDemo implements PasarelaPoint {
  PasarelaPointDemo({this.demora = const Duration(seconds: 3)});

  /// Lo que tarda en "pagar" el cliente.
  final Duration demora;
  final _creadas = <String, DateTime>{};
  var _siguiente = 0;

  @override
  Future<OrdenCobroCreada> crear({
    required String externalReference,
    required String idempotencyKey,
    required int montoCentavos,
    required String canal,
  }) async {
    final id = 'demo-${++_siguiente}';
    _creadas[id] = DateTime.now();
    return OrdenCobroCreada(ordenIdMp: id, estado: 'created');
  }

  @override
  Future<String> consultar(String ordenIdMp) async {
    final creada = _creadas[ordenIdMp];
    if (creada == null) return 'canceled';
    return DateTime.now().difference(creada) >= demora ? 'processed' : 'created';
  }

  @override
  Future<void> cancelar(String ordenIdMp) async => _creadas.remove(ordenIdMp);
}

/// Una sola para toda la demo: las órdenes creadas se consultan después desde otra pantalla.
final pasarelaPointDemo = PasarelaPointDemo();
