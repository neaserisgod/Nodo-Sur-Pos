import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/conciliacion_mp.dart';
import 'package:la_plazoleta/domain/saldo_mp.dart';

// Etapa E (El dueño, 2026-10-04): el saldo real de Mercado Pago llena el "MP contado" y las diferencias se avisan: lo que salió o
// entró de la cuenta y no está en la app, y lo registrado como cobrado por MP que no entró.

final _t = DateTime(2026, 10, 4, 12, 0);

MovimientoSaldoMp _mov({String tipo = 'release', String descripcion = 'payout', int credito = 0, int debito = 0, int minutos = 0, String? referencia}) =>
    MovimientoSaldoMp(
      fecha: _t.add(Duration(minutes: minutos)),
      tipo: tipo,
      descripcion: descripcion,
      creditoCentavos: credito,
      debitoCentavos: debito,
      referencia: referencia,
    );

MovimientoMpEnApp _app(int monto, {required bool salida, int minutos = 0}) => MovimientoMpEnApp(fecha: _t.add(Duration(minutes: minutos)), montoCentavos: monto, esSalida: salida);

void main() {
  group('SaldoMp', () {
    test('el MP contado sugerido es el total (disponible + a liberar); sin dato de lo a liberar, solo el disponible', () {
      const completo = SaldoMp(disponibleCentavos: 6000000, aLiberarCentavos: 244000, movimientos: [], hasta: null);
      expect(completo.totalCentavos, 6244000);
      expect(completo.contadoSugeridoCentavos, 6244000);
      const sin = SaldoMp(disponibleCentavos: 6000000, movimientos: [], hasta: null);
      expect(sin.totalCentavos, 6000000);
      expect(sin.aLiberarConocido, isFalse);
    });
  });

  group('compararSaldoMp', () {
    test('un egreso de la cuenta que no está en la app se avisa; uno cargado como gasto por MP no', () {
      final d = compararSaldoMp(
        movimientos: [_mov(debito: 6893571, descripcion: 'payment'), _mov(debito: 6604000, minutos: 1), _mov(debito: 6604000, minutos: 2)],
        enApp: [_app(6893571, salida: true), _app(6604000, salida: true, minutos: 1)],
        ventasSinCobro: const [],
      );
      expect(d.egresosSinRegistrar.map((m) => m.debitoCentavos), [6604000], reason: 'cada gasto de la app cubre un solo movimiento');
    });

    test('un cobro (crédito "payment") no es un ingreso sin registrar: eso lo conciliaron los cobros', () {
      final d = compararSaldoMp(
        movimientos: [_mov(descripcion: 'payment', credito: 5000), _mov(descripcion: 'loan', credito: 100000, minutos: 1)],
        enApp: const [],
        ventasSinCobro: const [],
      );
      expect(d.ingresosSinRegistrar.map((m) => m.descripcion), ['loan']);
    });

    test('un ingreso cargado como ingreso por MP lo cubre; un gasto del mismo monto no cubre un ingreso', () {
      final d = compararSaldoMp(
        movimientos: [_mov(descripcion: 'transfer', credito: 100000)],
        enApp: [_app(100000, salida: true)],
        ventasSinCobro: const [],
      );
      expect(d.ingresosSinRegistrar, hasLength(1));
      final d2 = compararSaldoMp(movimientos: [_mov(descripcion: 'transfer', credito: 100000)], enApp: [_app(100000, salida: false)], ventasSinCobro: const []);
      expect(d2.ingresosSinRegistrar, isEmpty);
    });

    test('se empareja con el más cercano en el tiempo', () {
      final d = compararSaldoMp(
        movimientos: [_mov(debito: 5000, minutos: 0), _mov(debito: 5000, minutos: 60)],
        enApp: [_app(5000, salida: true, minutos: 58)],
        ventasSinCobro: const [],
      );
      expect(d.egresosSinRegistrar.single.fecha, _t, reason: 'el de la hora 1 es el cubierto');
    });

    test('una devolución de la cuenta cubierta por una venta anulada de la app no se avisa', () {
      final d = compararSaldoMp(
        movimientos: [_mov(descripcion: 'refund', debito: 2000), _mov(descripcion: 'refund', debito: 3000, minutos: 1)],
        enApp: const [],
        anuladasEnApp: [_app(2000, salida: true)],
        ventasSinCobro: const [],
      );
      expect(d.egresosSinRegistrar.map((m) => m.debitoCentavos), [3000]);
    });

    test('las ventas cobradas por MP que no entraron pasan tal cual', () {
      final v = PagoMpRegistrado(ventaId: 433, fecha: _ayer, montoCentavos: 8194000);
      final d = compararSaldoMp(movimientos: const [], enApp: const [], ventasSinCobro: [v]);
      expect(d.ventasSinCobro.single.ventaId, 433);
      expect(d.hayDiferencias, isTrue);
      expect(compararSaldoMp(movimientos: const [], enApp: const [], ventasSinCobro: const []).hayDiferencias, isFalse);
    });

    test('un movimiento sin importe (o de ambos lados en cero) no avisa', () {
      final d = compararSaldoMp(movimientos: [_mov(), _mov(descripcion: 'x')], enApp: const [], ventasSinCobro: const []);
      expect(d.hayDiferencias, isFalse);
    });
  });
}

final _ayer = DateTime(2026, 10, 3, 19, 0);
