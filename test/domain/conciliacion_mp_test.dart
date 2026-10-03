// Conciliación de Mercado Pago: cada cobro real contra cada venta registrada por Mercado Pago.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/conciliacion_mp.dart';

DateTime _h(int hora, [int min = 0]) => DateTime(2026, 10, 1, hora, min);

CobroMp _cobro(String id, int monto, DateTime fecha, {String estado = 'approved', int devuelto = 0, int? comision}) {
  final c = comision ?? (monto * 2 ~/ 100);
  return CobroMp(id: id, estado: estado, fecha: fecha, montoCentavos: monto, devueltoCentavos: devuelto, comisionCentavos: c, netoCentavos: monto - devuelto - c, medio: 'account_money');
}

PagoMpRegistrado _venta(int id, int monto, DateTime fecha) => PagoMpRegistrado(ventaId: id, fecha: fecha, montoCentavos: monto, canal: 'qr');

void main() {
  test('todo emparejado: diferencia de cobros 0 y el esperado real descuenta solo comisiones', () {
    final c = conciliarMp(
      cobros: [_cobro('1', 360000, _h(11, 7)), _cobro('2', 1330000, _h(13, 21))],
      registrados: [_venta(373, 360000, _h(11, 7)), _venta(379, 1330000, _h(13, 21))],
    );
    expect(c.cantidadCobros, 2);
    expect(c.diferenciaCobrosCentavos, 0);
    expect(c.cobrosSinVenta, isEmpty);
    expect(c.ventasSinCobro, isEmpty);
    expect(c.comisionCentavos, 7200 + 26600);
    // Esperado del sistema 10.000 + 16.900 registrados → con comisiones: 10.000 + neto.
    expect(c.esperadoRealCentavos(1000000 + 1690000), 1000000 + 1690000 - 33800);
  });

  test('un cobro sin venta y una venta sin cobro se ven por separado', () {
    final c = conciliarMp(
      cobros: [_cobro('1', 360000, _h(11)), _cobro('2', 500000, _h(12))],
      registrados: [_venta(10, 360000, _h(11)), _venta(11, 720000, _h(15))],
    );
    expect(c.cobrosSinVenta.map((x) => x.id), ['2']);
    expect(c.ventasSinCobro.map((x) => x.ventaId), [11]);
    expect(c.diferenciaCobrosCentavos, 860000 - 1080000);
  });

  test('dos cobros del mismo monto: cada venta se queda con el más cercano en el tiempo, y uno no se usa dos veces', () {
    final c = conciliarMp(
      cobros: [_cobro('a', 360000, _h(11)), _cobro('b', 360000, _h(20, 30))],
      registrados: [_venta(1, 360000, _h(20, 29)), _venta(2, 360000, _h(20, 31))],
    );
    expect(c.ventasSinCobro, isEmpty);
    expect(c.cobrosSinVenta, isEmpty);
  });

  test('rechazados no suman ni emparejan; un devuelto entero no es plata sin venta', () {
    final c = conciliarMp(
      cobros: [
        _cobro('r', 360000, _h(11), estado: 'rejected'),
        _cobro('d', 200000, _h(12), estado: 'refunded', devuelto: 200000, comision: 0),
      ],
      registrados: [_venta(1, 360000, _h(11))],
    );
    expect(c.noCobrados, 1);
    expect(c.cantidadCobros, 1);
    expect(c.ventasSinCobro.map((x) => x.ventaId), [1], reason: 'el rechazado no cuenta como cobro');
    expect(c.cobrosSinVenta, isEmpty);
    expect(c.netoCentavos, 0);
  });
}
