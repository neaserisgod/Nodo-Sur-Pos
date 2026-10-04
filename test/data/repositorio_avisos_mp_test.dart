// Avisos de Mercado Pago guardados en la base (etapa D): sin duplicar, con cursor, "visto" y el cruce con las ventas reales.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_avisos_mp.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/avisos_mp.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

final _ahora = DateTime.now();

AvisoMp _aviso(int id, {TipoAvisoMp tipo = TipoAvisoMp.cobro, String? mpId, int? monto, String? referencia, String? estado, int minutos = 30}) => AvisoMp(
  idServidor: id,
  tipo: tipo,
  mpId: mpId ?? '$id',
  pagoId: tipo == TipoAvisoMp.cobro ? (mpId ?? '$id') : '1',
  montoCentavos: monto,
  referencia: referencia,
  estado: estado,
  creado: _ahora.subtract(Duration(minutes: minutos)),
  fecha: _ahora.subtract(Duration(minutes: minutos)),
);

void main() {
  test('guardar no duplica, el cursor es el último id y "visto" saca el aviso y sus versiones anteriores', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    expect(await ultimoIdAvisoMp(db), 0);
    expect(await guardarAvisosMp(db, [_aviso(1, monto: 100), _aviso(2, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', monto: 500, estado: 'documentacion')]), 2);
    expect(await guardarAvisosMp(db, [_aviso(2, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', monto: 500), _aviso(3, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', monto: 500, estado: 'abierto')]), 1,
        reason: 'el 2 ya estaba (llegó en vivo y otra vez por la consulta)');
    expect(await ultimoIdAvisoMp(db), 3);

    final antes = await avisosMpParaMostrar(db, ahora: _ahora);
    expect(antes.map((a) => a.aviso.idServidor).toSet(), {1, 3}, reason: 'del contracargo, solo la última versión');

    await marcarAvisoMpVisto(db, antes.firstWhere((a) => a.tipo == TipoAvisoMp.contracargo).aviso);
    expect((await avisosMpParaMostrar(db, ahora: _ahora)).map((a) => a.aviso.idServidor), [1]);

    await guardarAvisosMp(db, [_aviso(4, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', monto: 500, estado: 'abierto')]);
    expect((await avisosMpParaMostrar(db, ahora: _ahora)).map((a) => a.aviso.idServidor).toSet(), {1, 4}, reason: 'un aviso nuevo del mismo contracargo vuelve');
  });

  test('un cobro con una venta real de ese monto no avisa; sin venta (o con la venta anulada) sí', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    final virtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final pid = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(210000), stock: const Value(100)));
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(pid))).getSingle();
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    const config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);
    final v = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final res = calcularTotalVenta(venta: v, composicionPago: ComposicionPago.virtual, configRecargoCigarrillos: config, pasoRedondeoCentavos: 10000);
    final (ventaId, _) = await registrarVenta(db, venta: v, resultado: res, sesionCajaId: sesion, usuarioId: usuario,
        pagos: [PagoARegistrar(medioPagoId: virtual, montoCentavos: res.totalCentavos, esEfectivo: false, canal: 'qr')]);

    await guardarAvisosMp(db, [_aviso(1, monto: res.totalCentavos), _aviso(2, monto: 777700)]);
    expect((await avisosMpParaMostrar(db, ahora: _ahora)).map((a) => a.aviso.idServidor), [2], reason: 'el 1 tiene su venta; el 2 no');

    await anularVenta(db, ventaId: ventaId, usuarioId: usuario, motivo: 'prueba');
    expect((await avisosMpParaMostrar(db, ahora: _ahora)).map((a) => a.aviso.idServidor).toSet(), {1, 2}, reason: 'una venta anulada no cubre el cobro');
  });

  test('un cobro de una orden de la app que terminó en venta no avisa, aunque la venta tenga otro monto', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    final virtual = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final pid = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(210000), stock: const Value(100)));
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(pid))).getSingle();
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    const config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);
    final v = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final res = calcularTotalVenta(venta: v, composicionPago: ComposicionPago.virtual, configRecargoCigarrillos: config, pasoRedondeoCentavos: 10000);
    final (ventaId, _) = await registrarVenta(db, venta: v, resultado: res, sesionCajaId: sesion, usuarioId: usuario,
        pagos: [PagoARegistrar(medioPagoId: virtual, montoCentavos: res.totalCentavos, esEfectivo: false, canal: 'qr')]);
    await db.into(db.ordenesCobroPendientes).insert(OrdenesCobroPendientesCompanion.insert(
      externalReference: 'ref-1', idempotencyKey: 'idem-1', canal: 'qr', montoCentavos: res.totalCentavos, sesionCajaId: sesion,
      estado: const Value('aprobada'), ventaId: Value(ventaId),
    ));

    await guardarAvisosMp(db, [_aviso(1, monto: 1, referencia: 'ref-1')]);
    expect(await avisosMpParaMostrar(db, ahora: _ahora), isEmpty);
  });

  test('limpiar saca los de más de 30 días', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    await guardarAvisosMp(db, [_aviso(1, monto: 100, minutos: 60 * 24 * 31), _aviso(2, monto: 100)]);
    await limpiarAvisosMpViejos(db, ahora: _ahora);
    expect(await ultimoIdAvisoMp(db), 2);
    expect((await db.select(db.avisosMp).get()).map((f) => f.idServidor), [2]);
  });
}
