import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  group('registrarGastoRapido', () {
    test('con la sesión ABIERTA: graba el movimiento', () async {
      final id = await registrarGastoRapido(
        db,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 5000,
        medio: MedioGasto.cajonNormal,
      );

      final movimiento = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.id.equals(id))).getSingle();
      expect(movimiento.tipo, 'GASTO');
      expect(movimiento.montoCentavos, 5000);
    });

    test(
      'con la sesión ya CERRADA: tira SesionCerradaException, no graba nada',
      () async {
        // Bruno, 2026-09-19: "aislar los usuarios para que no se pisen" — un
        // gasto que llega justo después de un cierre (ej. desde otro
        // dispositivo) no debe grabarse contra una sesión ya cerrada.
        await (db.update(
          db.sesionesDeCaja,
        )..where((s) => s.id.equals(sesionId))).write(
          const SesionesDeCajaCompanion(estado: Value('CERRADA')),
        );

        await expectLater(
          registrarGastoRapido(
            db,
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            montoCentavos: 5000,
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
