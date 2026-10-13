// Los datos del tablero de la Agenda (`repositorio_tablero_agenda.dart`), sobre la barbería de la demo: dos barberos, turnos
// cobrados, por venir y esperando seña.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/demo/semilla_demo.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_tablero_agenda.dart';
import 'package:la_plazoleta/domain/tablero_agenda.dart';

Future<AppDatabase> _baseVacia() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.delete(db.configuracionNegocioTabla).go();
  await db.delete(db.categorias).go();
  await db.delete(db.usuarios).go();
  return db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a media tarde: turnos de hoy con precio, lo que falta cobrar y huecos para compartir', () async {
    final db = await _baseVacia();
    addTearDown(db.close);
    final ahora = DateTime(2026, 10, 13, 15, 10); // martes
    await sembrarNegocioDemo(db, NegocioDemo.barberia, ahora: ahora);

    final t = await tableroAgenda(db, ahora: ahora);
    expect(t.turnos, isNotEmpty);
    expect(t.turnos.every((x) => x.precioCentavos > 0), isTrue, reason: 'cada turno trae el precio de hoy de su servicio');
    expect(t.turnos.any((x) => x.atendido), isTrue, reason: 'los de la mañana se cobraron');
    expect(porCobrarCentavos(t.turnos), greaterThan(0));
    expect(proximoTurno(t.turnos, ahora), isNotNull);
    expect(t.textoHuecos, isNotNull);
    expect(t.textoHuecos, contains('Barbería El Faro'));
    expect(t.textoHuecos, contains('💈'));
  });

  test('a la noche no queda nada hoy: el texto arranca en mañana', () async {
    final db = await _baseVacia();
    addTearDown(db.close);
    final ahora = DateTime(2026, 10, 13, 23, 10);
    await sembrarNegocioDemo(db, NegocioDemo.barberia, ahora: ahora);

    final t = await tableroAgenda(db, ahora: ahora);
    expect(t.huecosHoy, 0);
    expect(proximoTurno(t.turnos, ahora), isNull);
    expect(t.textoHuecos, isNot(contains('Hoy:')));
  });
}
