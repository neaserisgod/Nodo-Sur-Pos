import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pendientes.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int medioEfectivoId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle())
            .id;
  });
  tearDown(() => db.close());

  group('Fiados', () {
    test('crear un fiado lo deja pendiente con nombre y monto', () async {
      await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);

      final lista = await listarFiados(db);
      expect(lista, hasLength(1));
      expect(lista.single.nombreLibre, 'Doña Rosa');
      expect(lista.single.montoCentavos, 5000);
      expect(lista.single.estado, 'PENDIENTE');
    });

    test('el total adeudado suma todos los fiados pendientes', () async {
      await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);
      await crearFiado(db, nombreLibre: 'Don Juan', montoCentavos: 3000, usuarioId: usuarioId);

      expect(await totalFiadosPendientesCentavos(db), 8000);
    });

    test('cobrar un fiado lo tilda como resuelto y genera una venta del monto exacto (Regla 15)', () async {
      final id =
          await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);

      final ventaId = await cobrarFiado(
        db,
        pendienteId: id,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        medioPagoId: medioEfectivoId,
        medioEsEfectivo: true,
      );

      final pendiente = await (db.select(db.pendientes)..where((p) => p.id.equals(id))).getSingle();
      expect(pendiente.estado, 'RESUELTO');
      expect(pendiente.ventaId, ventaId);
      expect(pendiente.fechaResuelta, isNotNull);

      final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
      expect(venta.totalCentavos, 5000);
      expect(venta.esFiado, isTrue);

      // No sigue apareciendo en la lista de pendientes.
      expect(await listarFiados(db), isEmpty);
      expect(await totalFiadosPendientesCentavos(db), 0);
    });

    test('la venta generada mueve la caja normal en efectivo, como cualquier cobro', () async {
      final id =
          await crearFiado(db, nombreLibre: 'Doña Rosa', montoCentavos: 5000, usuarioId: usuarioId);
      await cobrarFiado(
        db,
        pendienteId: id,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        medioPagoId: medioEfectivoId,
        medioEsEfectivo: true,
      );

      final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
      final movimientos = await (db.select(db.movimientosDeCaja)
            ..where((m) => m.sesionCajaId.equals(sesionId) & m.cajaId.equals(cajaNormal.id)))
          .get();
      expect(movimientos.single.montoCentavos, 5000);
    });
  });

  group('Encargues', () {
    test('crear un encargue lo deja pendiente con descripción', () async {
      await crearEncargue(db, nombreLibre: 'Don Juan', descripcion: 'Detergente 5L', usuarioId: usuarioId);

      final lista = await listarEncargues(db);
      expect(lista, hasLength(1));
      expect(lista.single.descripcion, 'Detergente 5L');
      expect(lista.single.estado, 'PENDIENTE');
    });

    test('resolver un encargue lo tilda sin generar ninguna venta', () async {
      final id =
          await crearEncargue(db, nombreLibre: 'Don Juan', descripcion: 'Detergente 5L', usuarioId: usuarioId);

      await resolverEncargue(db, id);

      final pendiente = await (db.select(db.pendientes)..where((p) => p.id.equals(id))).getSingle();
      expect(pendiente.estado, 'RESUELTO');
      expect(pendiente.ventaId, isNull);
      expect(await listarEncargues(db), isEmpty);
      expect(await (db.select(db.ventas)).get(), isEmpty);
    });
  });
}
