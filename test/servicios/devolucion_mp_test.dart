// Etapa B (2026-10-04): al anular una venta cobrada con la Point se ofrece devolverle la plata al cliente por Mercado Pago.
// Siempre por el sitio con la cuenta vinculada (el sitio decide si es dueño o encargado), nunca dos veces.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/devolucion_mp.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int ventaId;
  late int ordenId;

  setUp(() async {
    db = baseDeTest();
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    ventaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 820000, totalCentavos: 820000),
    );
    final p = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 820000);
    ordenId = p.id;
    await marcarOrdenConId(db, id: p.id, ordenIdMp: 'ORD-433');
    await marcarOrdenResuelta(db, id: p.id, estado: 'aprobada', ventaId: ventaId);
  });
  tearDown(() => db.close());

  Future<AlmacenCuentaEnMemoria> vinculada() async {
    final a = AlmacenCuentaEnMemoria();
    await a.guardar(const CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'pc-1', nombreDispositivo: 'Caja', vence: 1));
    return a;
  }

  ClienteNube sitio({bool canRefund = true, http.Response Function(http.Request)? devolver, List<http.Request>? pedidos}) =>
      ClienteNube(http: MockClient((r) async {
        pedidos?.add(r);
        if (r.url.path == '/api/mp/estado') {
          return http.Response(jsonEncode({'connected': true, 'needsReconnect': false, 'terminalConfigured': true, 'canRefund': canRefund}), 200);
        }
        if (r.url.path == '/api/mp/orden/devolver' && devolver != null) return devolver(r);
        return http.Response('{"error":"not_found"}', 404);
      }));

  group('cobroPointDeVenta', () {
    test('la venta cobrada con la Point trae su orden; una sin orden, null', () async {
      final c = await cobroPointDeVenta(db, ventaId);
      expect(c?.ordenIdMp, 'ORD-433');
      expect(c?.montoCentavos, 820000);
      expect(c?.devuelta, isFalse);
      expect(c?.ordenLocalId, ordenId);
      expect(await cobroPointDeVenta(db, ventaId + 99), isNull);
    });

    test('una orden que quedó pendiente (no se cobró) no se ofrece devolver', () async {
      await marcarOrdenResuelta(db, id: ordenId, estado: 'pendiente', ventaId: ventaId);
      expect(await cobroPointDeVenta(db, ventaId), isNull);
    });

    test('viaja de la PC al celular y la clave de devolución es la misma desde cualquier equipo', () async {
      final c = (await cobroPointDeVenta(db, ventaId))!;
      final enElCelular = CobroPoint.desdeJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>)!;
      expect(enElCelular.claveDevolucion, c.claveDevolucion);
      expect(c.claveDevolucion, matches(RegExp(r'^[\w-]{8,64}$')));
      expect(CobroPoint.desdeJson({'ordenIdMp': 1}), isNull, reason: 'datos raros: no se ofrece nada');
    });
  });

  group('puedeOfrecerDevolucion', () {
    test('solo con cuenta vinculada y si el sitio dice que quien la vinculó puede devolver', () async {
      final c = await cobroPointDeVenta(db, ventaId);
      expect(await puedeOfrecerDevolucion(c, almacen: await vinculada(), cliente: sitio()), isTrue);
      expect(await puedeOfrecerDevolucion(c, almacen: await vinculada(), cliente: sitio(canRefund: false)), isFalse, reason: 'un empleado');
      expect(await puedeOfrecerDevolucion(c, almacen: AlmacenCuentaEnMemoria(), cliente: sitio()), isFalse, reason: 'sin cuenta');
      expect(await puedeOfrecerDevolucion(null, almacen: await vinculada(), cliente: sitio()), isFalse, reason: 'a mano o en efectivo');
      final caido = ClienteNube(http: MockClient((_) async => http.Response('', 500)));
      expect(await puedeOfrecerDevolucion(c, almacen: await vinculada(), cliente: caido), isFalse, reason: 'ante la duda, no');
    });
  });

  group('devolverPorMp', () {
    test('devuelve con la clave fija y la anota; ya anotada no se vuelve a ofrecer', () async {
      final pedidos = <http.Request>[];
      final cliente = sitio(pedidos: pedidos, devolver: (r) => http.Response(jsonEncode({'id': 'ORD-433', 'status': 'refunded'}), 200));
      final c = (await cobroPointDeVenta(db, ventaId))!;
      final r = await devolverPorMp(c, almacen: await vinculada(), cliente: cliente, db: db);
      expect(r.resultado, ResultadoDevolucionMp.devuelta);
      final cuerpo = jsonDecode(pedidos.single.body) as Map<String, dynamic>;
      expect(cuerpo, {'id': 'ORD-433', 'idempotencyKey': c.claveDevolucion});
      expect((await cobroPointDeVenta(db, ventaId))!.devuelta, isTrue);
      expect(await puedeOfrecerDevolucion(await cobroPointDeVenta(db, ventaId), almacen: await vinculada(), cliente: sitio()), isFalse);
    });

    test('"ya devuelta" en Mercado Pago también se anota', () async {
      final cliente = sitio(devolver: (_) => http.Response('{"error":"ya_devuelta"}', 409));
      final r = await devolverPorMp((await cobroPointDeVenta(db, ventaId))!, almacen: await vinculada(), cliente: cliente, db: db);
      expect(r.resultado, ResultadoDevolucionMp.yaDevuelta);
      expect((await cobroPointDeVenta(db, ventaId))!.devuelta, isTrue);
    });

    test('sin permiso o con error no se anota nada', () async {
      final sinPermiso = sitio(devolver: (_) => http.Response('{"error":"sin_permiso_devolver"}', 403));
      expect((await devolverPorMp((await cobroPointDeVenta(db, ventaId))!, almacen: await vinculada(), cliente: sinPermiso, db: db)).resultado,
          ResultadoDevolucionMp.sinPermiso);
      final caido = sitio(devolver: (_) => http.Response('{"error":"mp_error"}', 502));
      final r = await devolverPorMp((await cobroPointDeVenta(db, ventaId))!, almacen: await vinculada(), cliente: caido, db: db);
      expect(r.resultado, ResultadoDevolucionMp.error);
      expect(r.mensaje, isNotNull);
      expect((await cobroPointDeVenta(db, ventaId))!.devuelta, isFalse);
    });
  });

  test('la orden devuelta sigue fuera de "sin resolver" del cierre', () async {
    await marcarOrdenDevuelta(db, ordenId);
    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    expect(await ordenesSinResolverDeSesion(db, venta.sesionCajaId), isEmpty);
  });
}
