// Seña de encargues, la parte de la plata (rediseño v4, etapa 8.4; plan y pruebas obligatorias en `docs/PLAN-SENA.md`).
// Lo que importa: cada caja cuadra todos los días, la seña nunca es una venta cuando entra, y la venta de la entrega es una sola,
// por el total, del día en que se completó.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_encargues.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int galletitas;
  late MedioDePago efectivo;
  late MedioDePago mp;

  Future<EstadoCajaEnVivo> estado([int? sesion]) => estadoCajaEnVivo(db, sesion ?? sesionId);

  Future<int> encargar({int sena = 0, bool enEfectivo = true, int cantidad = 4, int? sesion}) => crearEncargueApartando(
    db,
    nombreCliente: 'María',
    lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: cantidad)],
    usuarioId: usuarioId,
    senaCentavos: sena,
    senaEsEfectivo: enEfectivo,
    sesionCajaId: sesion ?? sesionId,
  );

  /// Entrega y cobra el encargue por el medio dado: lo que paga el cliente es el total menos la seña.
  Future<int> entregar(int encargueId, {required bool enEfectivo, int? sesion}) async {
    final lineas = await lineasParaEntregar(db, encargueId);
    final venta = Venta(lineas: lineas);
    final resultado = ResultadoTotalVenta(
      subtotalCentavos: venta.subtotalCentavos,
      recargoCigarrillosCentavos: 0,
      descuentoCentavos: 0,
      redondeoCentavos: 0,
      totalCentavos: venta.subtotalCentavos,
    );
    final sena = (await senaPendienteDe(db, encargueId)).centavos;
    final aCobrar = (resultado.totalCentavos - sena).clamp(0, resultado.totalCentavos);
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesion ?? sesionId,
      usuarioId: usuarioId,
      pagos: aCobrar == 0
          ? const []
          : [PagoARegistrar(medioPagoId: enEfectivo ? efectivo.id : mp.id, montoCentavos: aCobrar, esEfectivo: enEfectivo)],
      encargueId: encargueId,
    );
    return ventaId;
  }

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 1000000));
    galletitas = await crearProducto(db, nombre: 'Galletitas', precioCentavos: 150000, costoCentavos: 90000, stock: 10, usuarioId: usuarioId);
    efectivo = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
    mp = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
  });
  tearDown(() => db.close());

  group('al encargar con seña', () {
    test('en efectivo: sube el esperado del cajón, no el de Mercado Pago, y no hay ninguna venta', () async {
      final antes = await estado();
      await encargar(sena: 200000);
      final despues = await estado();
      expect(despues.efectivoEsperadoCentavos - antes.efectivoEsperadoCentavos, 200000);
      expect(despues.mpEsperadoCentavos, antes.mpEsperadoCentavos);
      expect(await db.select(db.ventas).get(), isEmpty);
    });

    test('por Mercado Pago: sube el esperado de MP y no el del cajón', () async {
      final antes = await estado();
      await encargar(sena: 200000, enEfectivo: false);
      final despues = await estado();
      expect(despues.mpEsperadoCentavos - antes.mpEsperadoCentavos, 200000);
      expect(despues.efectivoEsperadoCentavos, antes.efectivoEsperadoCentavos);
    });

    test('queda un ingreso de caja con el nombre del cliente', () async {
      await encargar(sena: 200000);
      final mov = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('INGRESO'))).getSingle();
      expect(mov.montoCentavos, 200000);
      expect(mov.nota, contains('María'));
    });

    test('una seña mayor a lo que vale lo apartado se rechaza y no deja nada a medias (ni stock ni caja)', () async {
      await expectLater(encargar(sena: 700000), throwsArgumentError); // 4 × 1.500 = 6.000
      expect((await (db.select(db.productos)..where((p) => p.id.equals(galletitas))).getSingle()).stock, 10);
      expect(await db.select(db.pendientes).get(), isEmpty);
      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });

    test('con seña pero sin caja abierta no se puede', () async {
      expect(
        () => crearEncargueApartando(
          db,
          nombreCliente: 'María',
          lineas: [LineaEncargueNueva(productoId: galletitas, cantidad: 1)],
          usuarioId: usuarioId,
          senaCentavos: 50000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('al cancelar', () {
    test('devuelve la seña por la misma caja: el esperado vuelve a donde estaba', () async {
      final base = await estado();
      final id = await encargar(sena: 200000);
      await cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: sesionId);
      final fin = await estado();
      expect(fin.efectivoEsperadoCentavos, base.efectivoEsperadoCentavos);
      expect(fin.mpEsperadoCentavos, base.mpEsperadoCentavos);
    });

    test('lo mismo por Mercado Pago', () async {
      final base = await estado();
      final id = await encargar(sena: 200000, enEfectivo: false);
      await cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: sesionId);
      expect((await estado()).mpEsperadoCentavos, base.mpEsperadoCentavos);
    });

    test('cancelar dos veces no devuelve dos veces', () async {
      final base = await estado();
      final id = await encargar(sena: 200000);
      await cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: sesionId);
      await cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: sesionId);
      expect((await estado()).efectivoEsperadoCentavos, base.efectivoEsperadoCentavos);
    });

    test('la devolución no es un gasto (no baja la ganancia): es su propio tipo', () async {
      final id = await encargar(sena: 200000);
      await cancelarEncargue(db, id, usuarioId: usuarioId, sesionCajaId: sesionId);
      expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('GASTO'))).get(), isEmpty);
      expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('DEVOLUCION_SENA'))).get(), hasLength(1));
    });

    test('con seña y sin caja abierta no se cancela (la plata no tendría de dónde salir)', () async {
      final id = await encargar(sena: 200000);
      await expectLater(cancelarEncargue(db, id, usuarioId: usuarioId), throwsArgumentError);
      expect(await listarEnarguesPendientes(db), hasLength(1), reason: 'sigue pendiente');
    });

    test('sin seña se cancela como siempre, sin pedir caja', () async {
      final id = await encargar();
      await cancelarEncargue(db, id, usuarioId: usuarioId);
      expect(await listarEnarguesPendientes(db), isEmpty);
    });
  });

  group('al entregar', () {
    test('en efectivo: solo entra lo que falta, la venta es por el total y la seña no se cuenta dos veces', () async {
      final base = await estado();
      final id = await encargar(sena: 200000); // total 600000
      final conSena = await estado();
      final ventaId = await entregar(id, enEfectivo: true);
      final fin = await estado();

      // Del cajón: la seña (200000) entró al señar y el resto (400000) al entregar = total, ni un centavo más.
      expect(fin.efectivoEsperadoCentavos - base.efectivoEsperadoCentavos, 600000);
      expect(fin.efectivoEsperadoCentavos - conSena.efectivoEsperadoCentavos, 400000);
      expect(fin.mpEsperadoCentavos, base.mpEsperadoCentavos);

      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.totalCentavos, 600000);
      final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(ventaId))).get();
      expect(pagos.fold<int>(0, (s, p) => s + p.montoCentavos), 600000, reason: 'los pagos suman el total');
      expect(pagos.where((p) => p.canal == 'sena').single.montoCentavos, 200000);
      expect(await listarEnarguesPendientes(db), isEmpty);
    });

    test('con la seña por Mercado Pago y el resto en efectivo: cada caja recibe lo suyo, una sola vez', () async {
      final base = await estado();
      final id = await encargar(sena: 200000, enEfectivo: false);
      await entregar(id, enEfectivo: true);
      final fin = await estado();
      expect(fin.mpEsperadoCentavos - base.mpEsperadoCentavos, 200000, reason: 'la seña de MP, solo la de cuando se señó');
      expect(fin.efectivoEsperadoCentavos - base.efectivoEsperadoCentavos, 400000);
    });

    test('seña igual al total: no se cobra nada más y la venta igual existe por el total', () async {
      final id = await encargar(sena: 600000);
      final antes = await estado();
      final ventaId = await entregar(id, enEfectivo: true);
      expect((await estado()).efectivoEsperadoCentavos, antes.efectivoEsperadoCentavos);
      expect((await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle()).totalCentavos, 600000);
    });

    test('seña mayor al total (bajó un precio): se devuelve la diferencia y el total de la venta es el nuevo', () async {
      final base = await estado();
      final id = await encargar(sena: 600000); // total 600000
      await (db.update(db.productos)..where((p) => p.id.equals(galletitas))).write(const ProductosCompanion(precioCentavos: Value(100000)));
      await entregar(id, enEfectivo: true); // ahora el total es 400000
      final fin = await estado();
      expect(fin.efectivoEsperadoCentavos - base.efectivoEsperadoCentavos, 400000, reason: 'el cajón queda con el total real');
      expect(await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('DEVOLUCION_SENA'))).get(), hasLength(1));
    });

    test('los pagos que no suman (total − seña) se rechazan: no se puede cobrar el total entero y además la seña', () async {
      final id = await encargar(sena: 200000);
      final venta = Venta(lineas: await lineasParaEntregar(db, id));
      await expectLater(
        registrarVenta(
          db,
          venta: venta,
          resultado: ResultadoTotalVenta(
            subtotalCentavos: venta.subtotalCentavos,
            recargoCigarrillosCentavos: 0,
            descuentoCentavos: 0,
            redondeoCentavos: 0,
            totalCentavos: venta.subtotalCentavos,
          ),
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          pagos: [PagoARegistrar(medioPagoId: efectivo.id, montoCentavos: venta.subtotalCentavos, esEfectivo: true)],
          encargueId: id,
        ),
        throwsArgumentError,
      );
    });

    test('Mercado Pago: la seña aplicada no cuenta como cobro nuevo en el esperado ni en la cantidad de ventas por MP', () async {
      final id = await encargar(sena: 200000, enEfectivo: false);
      final antes = await estado();
      await entregar(id, enEfectivo: true);
      expect((await estado()).mpEsperadoCentavos, antes.mpEsperadoCentavos);
      expect(await cantidadVentasPorMpDelDia(db, sesionId), 0);
    });

    test('una entrega sin seña funciona igual que siempre', () async {
      final id = await encargar();
      final base = await estado();
      await entregar(id, enEfectivo: true);
      expect((await estado()).efectivoEsperadoCentavos - base.efectivoEsperadoCentavos, 600000);
    });
  });

  group('cada día cuadra solo', () {
    test('señar ayer y entregar hoy: ayer queda con la seña y hoy solo con lo que falta', () async {
      final id = await encargar(sena: 200000);
      final ayer = await estado();
      // Se cierra la caja de ayer y se abre la de hoy.
      await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).write(const SesionesDeCajaCompanion(estado: Value('CERRADA')));
      final hoy = await db.into(db.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: ayer.efectivoEsperadoCentavos));
      final inicioHoy = await estado(hoy);

      await entregar(id, enEfectivo: true, sesion: hoy);
      final finHoy = await estado(hoy);
      expect(finHoy.efectivoEsperadoCentavos - inicioHoy.efectivoEsperadoCentavos, 400000, reason: 'hoy entra solo lo que faltaba');

      // La venta es de hoy, no de ayer.
      final ventas = await db.select(db.ventas).get();
      expect(ventas.single.sesionCajaId, hoy);
    });
  });

  group('una venta con seña no se edita ni se anula desde el historial', () {
    test('anular', () async {
      final id = await encargar(sena: 200000);
      final ventaId = await entregar(id, enEfectivo: true);
      await expectLater(anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: 'prueba'), throwsArgumentError);
    });
  });

  group('desde el celular (registrarVentaSegunMedio)', () {
    test('un encargue con seña se rechaza con un mensaje claro: se entrega desde la PC', () async {
      final id = await encargar(sena: 200000);
      await expectLater(
        registrarVentaSegunMedio(
          db,
          lineas: await lineasParaEntregar(db, id),
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          encargueId: id,
        ),
        throwsA(isA<EncargueConSena>()),
      );
    });
  });

  test('entregar a deuda un encargue con seña se rechaza (la seña no tendría dónde caer)', () async {
    final id = await encargar(sena: 200000);
    await expectLater(entregarEncargueADeuda(db, id, usuarioId: usuarioId), throwsA(isA<EncargueConSena>()));
  });
}
