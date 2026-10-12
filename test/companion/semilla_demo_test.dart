// La demo de horsepos.com/demo/ (`docs/PLAN-DEMO-SERVICIOS.md`): cada negocio de ejemplo se arma entero con los repositorios de
// la app, sin errores, y queda con algo para mostrar en cada pantalla.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/demo/semilla_demo.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/turnos.dart';

/// Una base como la del navegador: sin la configuración ni las categorías que siembra el escritorio.
Future<AppDatabase> _baseVacia() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.delete(db.configuracionNegocioTabla).go();
  await db.delete(db.categorias).go();
  await db.delete(db.usuarios).go();
  return db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final negocio in NegocioDemo.todos) {
    for (final hora in [8, 15, 23]) {
      test('${negocio.nombre}, abierta a las $hora', () async {
        final db = await _baseVacia();
        addTearDown(db.close);
        final ahora = DateTime(2026, 10, 12, hora, 10);
        final duenio = await sembrarNegocioDemo(db, negocio, ahora: ahora);

        expect(duenio.nombre, negocio.duenio);
        final config = await configuracionNegocioActual(db);
        expect(config.nombreComercio, negocio.nombre);
        expect(formaDeRubro(config.rubro), FormaDeTrabajo.servicios);

        final turnos = await turnosEntre(db, desde: DateTime(2026, 10, 12), hasta: DateTime(2026, 10, 19));
        expect(turnos.length, greaterThan(20), reason: 'la semana tiene que verse con vida');
        for (var d = 0; d < 7; d++) {
          expect(await turnosDelDia(db, DateTime(2026, 10, 12 + d)), isNotEmpty, reason: 'día $d sin turnos');
        }
        final estados = {for (final t in turnos) t.estado};
        expect(estados, contains(EstadoTurno.confirmado));
        expect(estados, contains(EstadoTurno.esperandoSena), reason: 'algún turno del bot esperando la seña');
        if (hora >= 15) expect(estados, contains(EstadoTurno.atendido), reason: 'a la tarde ya se cobró algo');
        if (hora == 8) expect(estados, isNot(contains(EstadoTurno.atendido)), reason: 'nada se cobra antes de que pase');
        // Ningún turno cobrado antes de terminar, ninguno abierto que ya terminó.
        for (final t in turnos) {
          if (t.estado == EstadoTurno.atendido) expect(t.fin.isAfter(ahora), isFalse);
          if (t.estado.abierto) expect(t.fin.isAfter(ahora), isTrue);
        }
        // Una misma persona nunca tiene dos turnos encima.
        final porPersona = <int?, List<TurnoAgenda>>{};
        for (final t in turnos) {
          (porPersona[t.turno.profesionalId] ??= []).add(t);
        }
        for (final lista in porPersona.values) {
          for (var i = 1; i < lista.length; i++) {
            expect(lista[i].inicio.isBefore(lista[i - 1].fin), isFalse, reason: '${lista[i - 1].turno.servicioNombre} y ${lista[i].turno.servicioNombre}');
          }
        }

        // Desde mañana siempre hay dónde dar un turno de media hora, aunque sea con "Cualquiera" (los dos libres).
        for (var d = 1; d < 7; d++) {
          final libres = await horariosLibresDelDia(db, DateTime(2026, 10, 12 + d), duracionMin: 30, ahora: ahora);
          expect(libres.length, greaterThanOrEqualTo(3), reason: 'día $d sin lugar para un turno nuevo');
        }

        final sesion = await sesionAbierta(db);
        expect(sesion, isNotNull, reason: 'la caja del día está abierta');
        final ventas = await db.select(db.ventas).get();
        expect(ventas.length, turnos.where((t) => t.estado == EstadoTurno.atendido).length);
      });
    }
  }

  test('con la misma hora, la misma agenda', () async {
    final a = await _baseVacia();
    final b = await _baseVacia();
    addTearDown(a.close);
    addTearDown(b.close);
    final ahora = DateTime(2026, 10, 14, 13);
    await sembrarNegocioDemo(a, NegocioDemo.peluqueria, ahora: ahora);
    await sembrarNegocioDemo(b, NegocioDemo.peluqueria, ahora: ahora);
    expect(await resumenDeTurnos(a), await resumenDeTurnos(b));
  });
}
