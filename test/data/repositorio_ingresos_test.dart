import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart' show MedioGasto;
import 'package:la_plazoleta/data/repositorio_ingresos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  group('registrarIngresoRapido', () {
    test('con la sesión ABIERTA: graba el movimiento', () async {
      final id = await registrarIngresoRapido(
        db,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 3000,
        medio: MedioGasto.cajonNormal,
      );

      final movimiento = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.id.equals(id))).getSingle();
      expect(movimiento.tipo, 'INGRESO');
      expect(movimiento.montoCentavos, 3000);
    });

    test(
      'con la sesión ya CERRADA: tira SesionCerradaException, no graba nada',
      () async {
        await (db.update(
          db.sesionesDeCaja,
        )..where((s) => s.id.equals(sesionId))).write(
          const SesionesDeCajaCompanion(estado: Value('CERRADA')),
        );

        await expectLater(
          registrarIngresoRapido(
            db,
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            montoCentavos: 3000,
            medio: MedioGasto.cajonNormal,
          ),
          throwsA(isA<SesionCerradaException>()),
        );

        final movimientos = await db.select(db.movimientosDeCaja).get();
        expect(movimientos, isEmpty);
      },
    );
  });
}
