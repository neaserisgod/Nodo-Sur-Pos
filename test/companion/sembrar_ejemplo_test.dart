// Cargar la barbería de ejemplo en una cuenta de verdad (`sembrar_ejemplo.dart`): solo sobre una base sin turnos, ventas ni
// cajas, y nunca encima de un negocio que ya trabaja.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/demo/sembrar_ejemplo.dart';
import 'package:la_plazoleta/companion/demo/semilla_demo.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart' as repo_servicios;
import 'package:la_plazoleta/data/repositorio_usuarios.dart' as repo_usuarios;
import 'package:la_plazoleta/data/repositorio_ventas.dart' as repo_ventas;
import 'package:la_plazoleta/companion/configurar/negocio_nuevo.dart' show guardarNegocio;
import 'package:la_plazoleta/domain/plantillas_rubro.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final ahora = DateTime(2026, 10, 13, 15, 10);

  test('una cuenta recién configurada (nombre, rubro y primer servicio) recibe la barbería entera', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final yo = await repo_usuarios.crearUsuario(db, 'Bruno');
    await guardarNegocio(db, nombre: 'Mi barbería', rubro: PlantillaRubro.barberia);
    await repo_servicios.crearServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, usuarioId: yo);

    expect(await sembrarEjemploEnCuenta(db, ahora: ahora), isTrue);

    expect((await configuracionNegocioActual(db)).nombreComercio, NegocioDemo.barberia.nombre);
    expect(await db.select(db.turnos).get(), isNotEmpty);
    expect(await db.select(db.ventas).get(), isNotEmpty);
    // Todo lo creado viaja por la sync.
    expect((await db.select(db.turnos).get()).every((t) => t.globalId != null), isTrue);
    expect((await db.select(db.ventas).get()).every((v) => v.globalId != null), isTrue);
  });

  test('con datos (una caja abierta) no carga sin confirmar; con "Cargar igual" carga y usa esa caja', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final yo = await repo_usuarios.crearUsuario(db, 'Bruno');
    await guardarNegocio(db, nombre: 'Mi barbería', rubro: PlantillaRubro.barberia);
    final caja = await repo_ventas.abrirSesion(db, usuarioId: yo, fondoInicialCentavos: 0);

    expect(await estadoParaEjemplo(db), EstadoParaEjemplo.conDatos);
    expect(await sembrarEjemploEnCuenta(db, ahora: ahora), isFalse);
    expect((await configuracionNegocioActual(db)).nombreComercio, 'Mi barbería');
    expect(await db.select(db.turnos).get(), isEmpty);

    expect(await sembrarEjemploEnCuenta(db, aunqueTengaDatos: true, ahora: ahora), isTrue);
    expect(await db.select(db.turnos).get(), isNotEmpty);
    final cajas = await db.select(db.sesionesDeCaja).get();
    expect(cajas.map((c) => c.id), [caja], reason: 'usa la caja que ya estaba abierta, no abre otra');
  });

  test('nunca se carga dos veces', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await repo_usuarios.crearUsuario(db, 'Bruno');
    await guardarNegocio(db, nombre: 'Mi barbería', rubro: PlantillaRubro.barberia);
    expect(await sembrarEjemploEnCuenta(db, ahora: ahora), isTrue);
    final servicios = (await db.select(db.productos).get()).where((p) => p.esServicio).length;

    expect(await estadoParaEjemplo(db), EstadoParaEjemplo.yaCargado);
    expect(await sembrarEjemploEnCuenta(db, aunqueTengaDatos: true, ahora: ahora), isFalse);
    expect((await db.select(db.productos).get()).where((p) => p.esServicio).length, servicios);
  });
}
