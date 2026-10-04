// Etapa E (El dueño, 2026-10-04): el saldo real de Mercado Pago llena el "MP contado" (editable) y las diferencias se avisan y se
// cargan con un toque como gasto o ingreso por MP.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/servicios/saldo_mp_nube.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_conciliacion_mp.dart' show LeerCobrosMp;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/conciliacion_mp.dart';
import 'package:la_plazoleta/domain/saldo_mp.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/ui/cierre/cierre_controlador.dart';
import '../../helpers/base_para_tests.dart';

SaldoMp _saldo({int disponible = 6000000, int? aLiberar = 244000, List<MovimientoSaldoMp> movimientos = const []}) =>
    SaldoMp(disponibleCentavos: disponible, aLiberarCentavos: aLiberar, movimientos: movimientos, hasta: DateTime.now());

MovimientoSaldoMp _egreso(int centavos, {String descripcion = 'payment'}) => MovimientoSaldoMp(
  fecha: DateTime.now(),
  tipo: 'release',
  descripcion: descripcion,
  creditoCentavos: 0,
  debitoCentavos: centavos,
);

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 100000);
  });
  tearDown(() => db.close());

  Future<CierreControlador> revelado(TraerSaldoMp? traer, {LeerCobrosMp? cobros}) async {
    final c = CierreControlador(db, sesionId: sesionId, traerSaldoMp: traer, leerCobrosMp: cobros);
    addTearDown(c.dispose);
    await c.cargar();
    c.efectivoContadoCtrl.text = '1.000';
    await c.confirmarConteo();
    return c;
  }

  test('traer el saldo llena el MP contado con el total en pesos enteros, y se puede corregir', () async {
    DateTime? pedidoDesde;
    final c = await revelado((desde) async {
      pedidoDesde = desde;
      return _saldo(disponible: 134421, aLiberar: 0); // $1.344,21
    });

    await c.traerSaldo();

    expect(pedidoDesde, c.sesion!.fechaApertura, reason: 'el reporte va desde que se abrió la caja');
    expect(c.mpContadoCtrl.text, '1.344');
    expect(c.saldoMp!.totalCentavos, 134421);
    expect(c.errorSaldo, isNull);
    expect(c.pidiendoSaldo, isFalse);

    c.mpContadoCtrl.text = '1.350'; // editable
    await Future<void>.delayed(Duration.zero);
    expect(c.resumen!.mpDiferenciaCentavos, isNotNull);
  });

  test('si el saldo falla lo dice y el MP contado queda como estaba; sin cuenta no hay botón', () async {
    final c = await revelado((_) async => throw const ErrorNube('mp_demora', 'El reporte de Mercado Pago todavía no está.'));
    c.mpContadoCtrl.text = '500';
    await c.traerSaldo();
    expect(c.errorSaldo, contains('todavía no está'));
    expect(c.mpContadoCtrl.text, '500');
    expect(c.saldoMp, isNull);

    final sin = await revelado(null);
    await sin.traerSaldo(); // no hace nada ni tira
    expect(sin.traerSaldoMp, isNull);
    expect(sin.saldoMp, isNull);
  });

  test('un egreso del reporte que la app no tiene se avisa y "cargar" lo anota como gasto por MP y baja el esperado', () async {
    final c = await revelado((_) async => _saldo(movimientos: [_egreso(6604000)]), cobros: (d, h) async => (cobros: <CobroMp>[], truncado: false));
    await c.traerSaldo();
    expect(c.diferenciasSaldo!.egresosSinRegistrar.single.debitoCentavos, 6604000);
    final esperadoAntes = c.resumen!.mpEsperadoCentavos;

    await c.cargarEgresoSinRegistrar(c.diferenciasSaldo!.egresosSinRegistrar.single);

    final gastos = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('GASTO'))).get();
    expect(gastos, hasLength(1));
    expect(gastos.single.montoCentavos, 6604000);
    expect(gastos.single.nota, contains('Movimiento en MP que no estaba en la app'));
    expect(gastos.single.sesionCajaId, sesionId);
    expect(c.diferenciasSaldo!.hayDiferencias, isFalse, reason: 'ya está en la app');
    expect(c.resumen!.mpEsperadoCentavos, esperadoAntes - 6604000, reason: 'el esperado de MP refleja el gasto cargado');
  });

  test('una venta marcada MP que no entró se puede cargar como gasto por MP y deja de listarse', () async {
    final virtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final pid = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(210000), stock: const Value(100)));
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(pid))).getSingle();
    final v = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final res = calcularTotalVenta(venta: v, composicionPago: ComposicionPago.virtual, configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000), pasoRedondeoCentavos: 10000);
    final (ventaId, _) = await registrarVenta(db, venta: v, resultado: res, sesionCajaId: sesionId, usuarioId: usuarioId,
        pagos: [PagoARegistrar(medioPagoId: virtual, montoCentavos: res.totalCentavos, esEfectivo: false, canal: 'qr')]);

    final c = await revelado((_) async => _saldo(), cobros: (d, h) async => (cobros: <CobroMp>[], truncado: false));
    await c.traerSaldo();
    expect(c.diferenciasSaldo!.ventasSinCobro.single.ventaId, ventaId);

    await c.cargarVentaSinCobroComoGasto(c.diferenciasSaldo!.ventasSinCobro.single);

    final gasto = (await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('GASTO'))).get()).single;
    expect(gasto.montoCentavos, res.totalCentavos);
    expect(gasto.nota, contains('Cobro marcado MP que no entró'));
    expect(c.diferenciasSaldo!.ventasSinCobro, isEmpty);
  });

  test('no se carga nada antes de revelar el cierre ni con la caja cerrada', () async {
    final c = CierreControlador(db, sesionId: sesionId, traerSaldoMp: (_) async => _saldo(movimientos: [_egreso(100)]));
    addTearDown(c.dispose);
    await c.cargar();
    await c.cargarEgresoSinRegistrar(_egreso(100));
    expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
  });
}
