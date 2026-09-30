import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
  });
  tearDown(() => db.close());

  test('arma el ticket con las líneas, el vendedor y el desglose de la venta persistida', () async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: Value(DateTime(2026, 8, 30, 15, 0)),
            subtotalCentavos: 224000,
            recargoCigarrillosCentavos: const Value(30000),
            redondeoCentavos: const Value(600),
            totalCentavos: 254600,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Coca-Cola 500ml',
            cantidad: const Value(2),
            precioUnitarioCentavos: 112000,
          ),
        );

    final ticket = await ticketDeVenta(db, ventaId);

    expect(ticket.vendedor, 'Dueño');
    expect(ticket.fecha, DateTime(2026, 8, 30, 15, 0));
    expect(ticket.lineas.single.nombreProducto, 'Coca-Cola 500ml');
    expect(ticket.lineas.single.subtotalCentavos, 224000);
    expect(ticket.desglose.recargoCigarrillosCentavos, 30000);
    expect(ticket.desglose.redondeoCentavos, 600);
    expect(ticket.totalCentavos, 254600);
  });

  test('una línea pesable arma el subtotal con el helper de pesables, no precio×gramos directo', () async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 41965,
            totalCentavos: 41965,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Jamón crudo',
            esPesable: const Value(true),
            gramos: const Value(350),
            precioUnitarioCentavos: 119900, // por kilo
          ),
        );

    final ticket = await ticketDeVenta(db, ventaId);

    expect(ticket.lineas.single.gramos, 350);
    expect(ticket.lineas.single.cantidad, 1);
    expect(ticket.lineas.single.subtotalCentavos, 41965); // redondeado hacia arriba por el helper de pesables
  });

  group('configuración de impresión', () {
    test('guarda y lee el access token, terminal id y carpeta de tickets', () async {
      await configurarMpAccessToken(db, 'TOKEN-X');
      await configurarMpTerminalId(db, 'TERM-X');
      await configurarCarpetaTickets(db, 'C:/tickets');

      final config = await db.select(db.configuracionTabla).getSingle();
      expect(config.mpAccessToken, 'TOKEN-X');
      expect(config.mpTerminalId, 'TERM-X');
      expect(config.rutaTicketsCarpeta, 'C:/tickets');
    });
  });

  group('buscarVentasParaReimprimir', () {
    Future<int> crearVentaEn(DateTime fecha) {
      return db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: Value(fecha),
              subtotalCentavos: 1000,
              totalCentavos: 1000,
            ),
          );
    }

    test('por número exacto, trae solo esa venta', () async {
      await crearVentaEn(DateTime(2026, 8, 29));
      final id2 = await crearVentaEn(DateTime(2026, 8, 30));

      final resultado = await buscarVentasParaReimprimir(db, numero: id2);

      expect(resultado, hasLength(1));
      expect(resultado.single.id, id2);
    });

    test('por fecha, trae solo las ventas de ese día (no de otros)', () async {
      await crearVentaEn(DateTime(2026, 8, 29, 23, 59));
      final idDelDia = await crearVentaEn(DateTime(2026, 8, 30, 10, 0));
      await crearVentaEn(DateTime(2026, 8, 31, 0, 0));

      final resultado = await buscarVentasParaReimprimir(db, fecha: DateTime(2026, 8, 30));

      expect(resultado.map((v) => v.id), [idDelDia]);
    });

    test('sin filtros, trae las últimas ventas para no dejar la pantalla vacía', () async {
      await crearVentaEn(DateTime(2026, 8, 29));
      await crearVentaEn(DateTime(2026, 8, 30));

      final resultado = await buscarVentasParaReimprimir(db);

      expect(resultado, hasLength(2));
    });
  });
}
