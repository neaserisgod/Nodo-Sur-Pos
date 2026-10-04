import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/avisos_mp.dart';

// Etapa D (El dueño, 2026-10-04): la campanita avisa de un cobro que entró a Mercado Pago y no tiene venta, y de un contracargo
// o reclamo con la venta cruzada. No toca la caja ni el stock.

final _ahora = DateTime(2026, 10, 4, 15, 0);

AvisoMp _aviso({
  int id = 1,
  TipoAvisoMp tipo = TipoAvisoMp.cobro,
  String mpId = '9001',
  String? pagoId,
  int? monto = 123450,
  String? referencia,
  String? estado,
  String? detalle,
  DateTime? fecha,
  DateTime? creado,
  bool visto = false,
}) => AvisoMp(
  idServidor: id,
  tipo: tipo,
  mpId: mpId,
  pagoId: pagoId ?? (tipo == TipoAvisoMp.cobro ? mpId : null),
  montoCentavos: monto,
  referencia: referencia,
  estado: estado,
  detalle: detalle,
  fecha: fecha ?? _ahora.subtract(const Duration(minutes: 30)),
  creado: creado ?? _ahora.subtract(const Duration(minutes: 30)),
  visto: visto,
);

VentaMp _venta(int id, int monto, {String? numero, DateTime? fecha}) =>
    VentaMp(ventaId: id, numero: numero ?? 'K7-000$id', fecha: fecha ?? _ahora.subtract(const Duration(minutes: 31)), montoCentavos: monto);

List<AvisoParaMostrar> _calcular(
  List<AvisoMp> avisos, {
  List<OrdenConocida> ordenes = const [],
  List<VentaMp> ventas = const [],
}) => avisosParaMostrar(avisos: avisos, ordenes: ordenes, ventas: ventas, ahora: _ahora);

void main() {
  group('cobro sin venta', () {
    test('un cobro que no coincide con ninguna venta avisa, con el monto', () {
      final r = _calcular([_aviso()]);
      expect(r, hasLength(1));
      expect(r.single.tipo, TipoAvisoMp.cobro);
      expect(r.single.titulo, contains('1.235'));
      expect(r.single.texto, contains('no hay una venta'));
      expect(r.single.ventaNumero, isNull);
    });

    test('un cobro con una venta del mismo monto (cobro a mano) no avisa', () {
      expect(_calcular([_aviso()], ventas: [_venta(7, 123450)]), isEmpty);
    });

    test('una venta no tapa a dos cobros del mismo monto: el segundo sí avisa', () {
      final r = _calcular([_aviso(id: 1, mpId: '1'), _aviso(id: 2, mpId: '2')], ventas: [_venta(7, 123450)]);
      expect(r, hasLength(1));
    });

    test('un cobro de una orden de la app que terminó en venta no avisa', () {
      final r = _calcular(
        [_aviso(referencia: 'ref-1')],
        ordenes: const [OrdenConocida(referencia: 'ref-1', ventaId: 7)],
        ventas: [_venta(7, 123450)],
      );
      expect(r, isEmpty);
    });

    test('la venta de esa orden no tapa a otro cobro sin venta del mismo monto', () {
      final r = _calcular(
        [_aviso(id: 1, mpId: '1', referencia: 'ref-1'), _aviso(id: 2, mpId: '2')],
        ordenes: const [OrdenConocida(referencia: 'ref-1', ventaId: 7)],
        ventas: [_venta(7, 123450)],
      );
      expect(r.map((a) => a.aviso.mpId), ['2']);
    });

    test('una orden de la app sin venta (la PC se cerró antes de grabarla) sí avisa', () {
      final r = _calcular([_aviso(referencia: 'ref-1')], ordenes: const [OrdenConocida(referencia: 'ref-1')]);
      expect(r, hasLength(1));
    });

    test('espera unos minutos antes de avisar: la venta se graba recién al terminar de cobrar', () {
      final reciente = _aviso(creado: _ahora.subtract(const Duration(minutes: 2)));
      expect(_calcular([reciente]), isEmpty);
      expect(_calcular([_aviso(creado: _ahora.subtract(const Duration(minutes: 6)))]), hasLength(1));
    });

    test('lo marcado como visto no vuelve', () {
      expect(_calcular([_aviso(visto: true)]), isEmpty);
    });

    test('sin monto no se puede cruzar con una venta: avisa igual', () {
      expect(_calcular([_aviso(monto: null)], ventas: [_venta(7, 123450)]), hasLength(1));
    });
  });

  group('contracargos y reclamos', () {
    test('un contracargo se cruza con la venta por la referencia de su orden', () {
      final r = _calcular(
        [_aviso(id: 3, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', pagoId: '9001', referencia: 'ref-1', estado: 'documentacion')],
        ordenes: const [OrdenConocida(referencia: 'ref-1', ventaId: 7)],
        ventas: [_venta(7, 123450, numero: 'K7-0123')],
      );
      expect(r.single.tipo, TipoAvisoMp.contracargo);
      expect(r.single.ventaNumero, 'K7-0123');
      expect(r.single.ventaId, 7);
      expect(r.single.titulo, contains('Contracargo'));
      expect(r.single.texto, contains('K7-0123'));
      expect(r.single.texto, contains('documentación'));
    });

    test('sin referencia, se cruza por el monto y lo dice como "podría ser"', () {
      final r = _calcular(
        [_aviso(id: 3, tipo: TipoAvisoMp.reclamo, mpId: 'CL1', pagoId: '9001', estado: 'opened')],
        ventas: [_venta(7, 123450, numero: 'K7-0123')],
      );
      expect(r.single.ventaNumero, 'K7-0123');
      expect(r.single.texto, contains('Podría ser'));
      expect(r.single.titulo, contains('Reclamo'));
    });

    test('sin venta que cruzar avisa igual, diciendo que no se encontró', () {
      final r = _calcular([_aviso(id: 3, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', pagoId: '9001', estado: 'abierto')]);
      expect(r.single.ventaNumero, isNull);
      expect(r.single.texto, contains('No encontré'));
    });

    test('un aviso nuevo del mismo contracargo reemplaza al anterior y vuelve a aparecer aunque el viejo esté visto', () {
      final r = _calcular([
        _aviso(id: 3, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', estado: 'documentacion', visto: true),
        _aviso(id: 4, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', estado: 'abierto'),
      ]);
      expect(r, hasLength(1));
      expect(r.single.aviso.idServidor, 4);
    });

    test('si el último ya está visto, no queda nada', () {
      final r = _calcular([
        _aviso(id: 3, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', estado: 'documentacion'),
        _aviso(id: 4, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', estado: 'abierto', visto: true),
      ]);
      expect(r, isEmpty);
    });

    test('un reclamo cerrado lo dice', () {
      final r = _calcular([_aviso(id: 3, tipo: TipoAvisoMp.reclamo, mpId: 'CL1', estado: 'closed')]);
      expect(r.single.texto, contains('cerrado'));
    });
  });

  test('lo más nuevo primero', () {
    final r = _calcular([
      _aviso(id: 1, mpId: '1', monto: 100, creado: _ahora.subtract(const Duration(hours: 2))),
      _aviso(id: 2, tipo: TipoAvisoMp.reclamo, mpId: 'CL1', creado: _ahora.subtract(const Duration(hours: 1))),
    ]);
    expect(r.map((a) => a.aviso.idServidor), [2, 1]);
  });
}
