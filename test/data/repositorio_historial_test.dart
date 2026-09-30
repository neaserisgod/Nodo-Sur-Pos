import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_historial.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int medioEfectivoId;
  late int medioMpId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<int> crearSesionCerrada({int? diferencia}) {
    return db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
            estado: const Value('CERRADA'),
            diferenciaCentavos: Value(diferencia),
          ),
        );
  }

  Future<int> crearVenta(int sesionId, {required int totalCentavos, required int medioPagoId, DateTime? fecha}) async {
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: fecha == null ? const Value.absent() : Value(fecha),
            subtotalCentavos: totalCentavos,
            totalCentavos: totalCentavos,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            precioUnitarioCentavos: totalCentavos,
          ),
        );
    await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioPagoId, montoCentavos: totalCentavos),
        );
    return ventaId;
  }

  group('listarDias', () {
    test('trae solo sesiones cerradas, con lo esencial de cada una', () async {
      final abierta = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      final cerrada = await crearSesionCerrada(diferencia: -500);
      await crearVenta(cerrada, totalCentavos: 100000, medioPagoId: medioEfectivoId);
      await crearVenta(cerrada, totalCentavos: 50000, medioPagoId: medioMpId);

      final dias = await listarDias(db);

      expect(dias.map((d) => d.sesion.id), isNot(contains(abierta)));
      final dia = dias.singleWhere((d) => d.sesion.id == cerrada);
      expect(dia.totalVendidoCentavos, 150000);
      expect(dia.efectivoCentavos, 100000);
      expect(dia.mpCentavos, 50000);
      expect(dia.diferenciaCentavos, -500);
    });

    test('ordena del día más reciente al más viejo', () async {
      await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
              fechaApertura: Value(DateTime(2026, 8, 1)),
              estado: const Value('CERRADA'),
            ),
          );
      await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
              fechaApertura: Value(DateTime(2026, 8, 30)),
              estado: const Value('CERRADA'),
            ),
          );

      final dias = await listarDias(db);
      expect(dias.first.sesion.fechaApertura, DateTime(2026, 8, 30));
    });

    test('cigarrillos: suma el precio de lista de líneas de cigarrillo del día', () async {
      final sesionId = await crearSesionCerrada();
      final ventaId = await crearVenta(sesionId, totalCentavos: 350000, medioPagoId: medioEfectivoId);
      await (db.update(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId)))
          .write(const LineasDeVentaCompanion(tipoCigarrillo: Value('atado')));

      final dia = (await listarDias(db)).single;
      expect(dia.cigarrillosCentavos, 350000);
    });
  });

  group('detalle de un día', () {
    test('ventasDelDia trae las ventas de esa sesión, ordenadas por hora', () async {
      final sesionId = await crearSesionCerrada();
      await crearVenta(sesionId, totalCentavos: 1000, medioPagoId: medioEfectivoId, fecha: DateTime(2026, 8, 30, 15, 0));
      await crearVenta(sesionId, totalCentavos: 2000, medioPagoId: medioEfectivoId, fecha: DateTime(2026, 8, 30, 10, 0));

      final ventas = await ventasDelDia(db, sesionId);

      expect(ventas.map((v) => v.totalCentavos), [2000, 1000]);
    });
  });
}
