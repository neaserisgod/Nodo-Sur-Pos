// Revisión de blindaje (2026-10-04): lo que mueve plata no se puede hacer dos veces ni a medias.
//
//  * Un fiado se cobra UNA vez (antes dos toques casi simultáneos —PC y celular, o doble clic— grababan dos ventas).
//  * Una venta cuyos pagos no suman su total no se graba (descuadraría la caja y Mercado Pago).
//  * Una orden de la Point se marca aprobada en la MISMA transacción que su venta, y confirmarla dos veces devuelve la
//    misma venta (un reintento del celular no duplica el cobro).
//  * Un pago a proveedor con montos imposibles se rechaza.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import 'package:la_plazoleta/data/repositorio_pendientes.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;
  late int productoId;

  Future<int> ventasContadas() async => (await db.select(db.ventas).get()).length;

  LineaVentaPorUnidad linea(int cantidad) => LineaVentaPorUnidad(
        productoId: '$productoId',
        nombreProducto: 'Coca',
        proveedorId: null,
        cantidad: cantidad,
        precioUnitarioCentavos: 100000,
      );

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Coca', precioCentavos: const Value(100000), stock: const Value(10)),
        );
  });
  tearDown(() => db.close());

  group('cobrar un fiado', () {
    test('una segunda vez no graba otra venta: tira PendienteYaResueltoException', () async {
      final id = await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);
      Future<int> cobrar() => cobrarFiado(
            db,
            pendienteId: id,
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            medioPagoId: medioEfectivoId,
            medioEsEfectivo: true,
          );

      final ventaId = await cobrar();
      await expectLater(cobrar(), throwsA(isA<PendienteYaResueltoException>()));

      expect(await ventasContadas(), 1, reason: 'una sola venta por el fiado');
      final pendiente = await (db.select(db.pendientes)..where((p) => p.id.equals(id))).getSingle();
      expect(pendiente.ventaId, ventaId);
    });

    test('dos toques casi a la vez (PC y celular): gana uno, el otro se entera y no hay doble cobro', () async {
      final id = await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);
      Future<Object> cobrar() => cobrarFiado(
            db,
            pendienteId: id,
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            medioPagoId: medioEfectivoId,
            medioEsEfectivo: true,
          ).then<Object>((v) => v).catchError((Object e) => e);

      final resultados = await Future.wait([cobrar(), cobrar()]);

      expect(resultados.whereType<int>(), hasLength(1));
      expect(resultados.whereType<PendienteYaResueltoException>(), hasLength(1));
      expect(await ventasContadas(), 1);
      final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('VENTA'))).get();
      expect(movimientos.fold<int>(0, (s, m) => s + m.montoCentavos), 5000, reason: 'la caja sumó el fiado una sola vez');
    });

    test('un encargue no es un fiado: no se cobra como si lo fuera', () async {
      final id = await crearEncargue(db, nombreLibre: 'Don Juan', descripcion: '2 kg de pan', usuarioId: usuarioId);
      await expectLater(
        cobrarFiado(db, pendienteId: id, sesionCajaId: sesionId, usuarioId: usuarioId, medioPagoId: medioEfectivoId, medioEsEfectivo: true),
        throwsA(isA<ArgumentError>()),
      );
      expect(await ventasContadas(), 0);
    });

    test('un fiado que no existe tira ArgumentError (no un "Bad state" suelto)', () async {
      await expectLater(
        cobrarFiado(db, pendienteId: 9999, sesionCajaId: sesionId, usuarioId: usuarioId, medioPagoId: medioEfectivoId, medioEsEfectivo: true),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('registrarVenta: invariantes', () {
    test('pagos que no suman el total no se graban, y no queda nada a medias', () async {
      await expectLater(
        registrarVenta(
          db,
          venta: Venta(lineas: [linea(1)]),
          resultado: const ResultadoTotalVenta(
            subtotalCentavos: 100000,
            recargoCigarrillosCentavos: 0,
            redondeoCentavos: 0,
            totalCentavos: 100000,
          ),
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: 99000, esEfectivo: true)],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await ventasContadas(), 0);
      expect((await db.select(db.pagos).get()), isEmpty);
      expect((await db.select(db.movimientosDeStock).get()), isEmpty);
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
      expect(producto.stock, 10, reason: 'el stock no se tocó');
    });

    test('con los pagos exactos sí se graba (el invariante no rompe lo normal)', () async {
      final (ventaId, _) = await registrarVenta(
        db,
        venta: Venta(lineas: [linea(1)]),
        resultado: const ResultadoTotalVenta(
          subtotalCentavos: 100000,
          recargoCigarrillosCentavos: 0,
          redondeoCentavos: 0,
          totalCentavos: 100000,
        ),
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: 100000, esEfectivo: true)],
      );
      expect(ventaId, greaterThan(0));
    });
  });

  group('orden de la Point ↔ venta', () {
    test('la venta y su orden quedan aprobada/ligada en la misma transacción', () async {
      final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);

      final r = await registrarVentaSegunMedio(
        db,
        lineas: [linea(1)],
        medio: ComposicionPago.virtual,
        canal: 'qr',
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        ordenCobroPendienteId: pendiente.id,
      );

      final orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
      expect(orden.estado, 'aprobada');
      expect(orden.ventaId, r.ventaId);
    });

    test('confirmar dos veces la misma orden devuelve la misma venta y no duplica nada', () async {
      final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      Future<({int ventaId, int totalCentavos})> confirmar() => registrarVentaSegunMedio(
            db,
            lineas: [linea(1)],
            medio: ComposicionPago.virtual,
            canal: 'qr',
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            ordenCobroPendienteId: pendiente.id,
          );

      final primera = await confirmar();
      final segunda = await confirmar();

      expect(segunda.ventaId, primera.ventaId);
      expect(segunda.totalCentavos, primera.totalCentavos);
      expect(await ventasContadas(), 1);
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
      expect(producto.stock, 9, reason: 'el stock bajó una sola vez');
    });

    test('dos confirmaciones simultáneas (reintento del celular) tampoco duplican', () async {
      final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      Future<({int ventaId, int totalCentavos})> confirmar() => registrarVentaSegunMedio(
            db,
            lineas: [linea(1)],
            medio: ComposicionPago.virtual,
            canal: 'qr',
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            ordenCobroPendienteId: pendiente.id,
          );

      final r = await Future.wait([confirmar(), confirmar()]);

      expect(r[0].ventaId, r[1].ventaId);
      expect(await ventasContadas(), 1);
    });

    test('una orden que no existe tira ArgumentError y no graba la venta', () async {
      await expectLater(
        registrarVentaSegunMedio(
          db,
          lineas: [linea(1)],
          medio: ComposicionPago.virtual,
          canal: 'qr',
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          ordenCobroPendienteId: 4242,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await ventasContadas(), 0);
    });
  });

  group('crearOrdenPendiente: reintento después de un corte', () {
    test('un intento sin respuesta (sin id de Mercado Pago) reciente se reutiliza: misma clave, nunca dos órdenes', () async {
      final primera = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      final segunda = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);

      expect(segunda.id, primera.id);
      expect(segunda.idempotencyKey, primera.idempotencyKey);
      expect(segunda.externalReference, primera.externalReference);
      expect((await db.select(db.ordenesCobroPendientes).get()), hasLength(1));
    });

    test('con otro monto o canal es otro cobro: no se reutiliza', () async {
      final primera = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      final otroMonto = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100100);
      final otroCanal = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'debit_card', montoCentavos: 100000);

      expect({primera.id, otroMonto.id, otroCanal.id}, hasLength(3));
    });

    test('una que ya tiene orden en Mercado Pago, o ya se resolvió, no se reutiliza', () async {
      final conId = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      await marcarOrdenConId(db, id: conId.id, ordenIdMp: 'ORD1');
      expect((await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000)).id, isNot(conId.id));

      await db.delete(db.ordenesCobroPendientes).go();
      final rechazada = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      await marcarOrdenResuelta(db, id: rechazada.id, estado: 'rechazada');
      expect((await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000)).id, isNot(rechazada.id));
    });

    test('pasado el vencimiento de la orden (2 minutos) ya no se reutiliza: Mercado Pago la venció sola', () async {
      final vieja = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      await (db.update(db.ordenesCobroPendientes)..where((o) => o.id.equals(vieja.id))).write(
        OrdenesCobroPendientesCompanion(creadaEn: Value(DateTime.now().subtract(const Duration(minutes: 5)))),
      );
      expect((await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000)).id, isNot(vieja.id));
    });

    test('otra sesión de caja no reutiliza nada', () async {
      final primera = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 100000);
      final otraSesion = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0, estado: const Value('CERRADA')),
          );
      expect((await crearOrdenPendiente(db, sesionCajaId: otraSesion, canal: 'qr', montoCentavos: 100000)).id, isNot(primera.id));
    });
  });

  group('pagar a un proveedor: montos imposibles', () {
    test('un monto negativo, o una parte de Mercado Pago mayor al pago, se rechaza sin tocar nada', () async {
      final proveedorId = (await db.select(db.proveedores).get()).first.id;
      for (final (monto, mp) in [(-1, null), (1000, 2000), (1000, -5)]) {
        await expectLater(
          pagarProveedor(db, proveedorId: proveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: monto, montoMpCentavos: mp),
          throwsA(isA<ArgumentError>()),
          reason: 'monto $monto, mp $mp',
        );
      }
      expect((await db.select(db.movimientosDeCaja).get()).where((m) => m.tipo == 'PAGO_PROVEEDOR'), isEmpty);
    });
  });
}
