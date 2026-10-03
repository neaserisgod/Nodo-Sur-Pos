// Lo registrado por Mercado Pago en un turno (sin efectivo ni anuladas) y la conciliación con el rango del turno.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_conciliacion_mp.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/conciliacion_mp.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

void main() {
  test('solo pagos no en efectivo de ventas vigentes, y el rango va de la apertura al cierre', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    final efectivo = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final virtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final pid = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(210000), stock: const Value(100)));
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(pid))).getSingle();
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    const config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

    Future<int> vender(bool qr) async {
      final v = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
      final res = calcularTotalVenta(venta: v, composicionPago: qr ? ComposicionPago.virtual : ComposicionPago.efectivo, configRecargoCigarrillos: config, pasoRedondeoCentavos: 10000);
      final (id, _) = await registrarVenta(db, venta: v, resultado: res, sesionCajaId: sesion, usuarioId: usuario,
          pagos: [PagoARegistrar(medioPagoId: qr ? virtual : efectivo, montoCentavos: res.totalCentavos, esEfectivo: !qr, canal: qr ? 'qr' : null)]);
      return id;
    }

    final qr1 = await vender(true);
    await vender(false);
    final qr2 = await vender(true);
    await anularVenta(db, ventaId: qr2, usuarioId: usuario, motivo: 'prueba');

    final registrados = await pagosMpRegistrados(db, sesion);
    expect(registrados.map((r) => r.ventaId), [qr1]);
    expect(registrados.single.canal, 'qr');

    DateTime? desde, hasta;
    final ahora = DateTime(2030);
    final c = await conciliarMpDeSesion(db, sesion, (d, h) async {
      desde = d;
      hasta = h;
      return (cobros: [CobroMp(id: '1', estado: 'approved', fecha: DateTime.now(), montoCentavos: registrados.single.montoCentavos, devueltoCentavos: 0, comisionCentavos: 100, netoCentavos: registrados.single.montoCentavos - 100)], truncado: false);
    }, ahora: ahora);
    final s = await (db.select(db.sesionesDeCaja)..where((x) => x.id.equals(sesion))).getSingle();
    expect(desde, s.fechaApertura);
    expect(hasta, ahora, reason: 'turno abierto: hasta ahora');
    expect(c.diferenciaCobrosCentavos, 0);
    expect(c.comisionCentavos, 100);
  });
}
