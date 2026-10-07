import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/base_para_tests.dart';

/// Recuperar la marca de cigarrillo que borraba editar desde el celular (El dueño, 2026-10-07).
void main() {
  Future<void> vender(AppDatabase db, int sesion, int usuario, int productoId, String tipo, DateTime fecha) async {
    final venta = await db.into(db.ventas).insert(
          VentasCompanion.insert(sesionCajaId: sesion, usuarioId: usuario, fecha: Value(fecha), subtotalCentavos: 100, totalCentavos: 100),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: venta,
            productoId: Value(productoId),
            nombreProductoFoto: 'x',
            tipoCigarrillo: Value(tipo),
            cantidad: const Value(1),
            precioUnitarioCentavos: 100,
          ),
        );
  }

  Future<Producto> producto(AppDatabase db, int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

  test('vuelve a marcar con la última venta marcada; no toca lo que nunca fue cigarrillo ni lo ya marcado', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuario = (await db.select(db.usuarios).get()).first.id;
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    final marlboro = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Marlboro'));
    final sueltos = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Sueltos'));
    final coca = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Coca'));
    final camel = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Camel', tipoCigarrillo: const Value('atado')));

    // Marlboro: se vendió marcado, después se le borró la marca y se vendió sin ella.
    await vender(db, sesion, usuario, marlboro, 'atado', DateTime(2026, 10, 1));
    await vender(db, sesion, usuario, marlboro, 'ninguno', DateTime(2026, 10, 5));
    await vender(db, sesion, usuario, sueltos, 'atado', DateTime(2026, 9, 1));
    await vender(db, sesion, usuario, sueltos, 'suelto', DateTime(2026, 10, 2));
    await vender(db, sesion, usuario, coca, 'ninguno', DateTime(2026, 10, 2));
    await vender(db, sesion, usuario, camel, 'suelto', DateTime(2026, 10, 2));

    final recuperados = await recuperarMarcaDeCigarrillos(db);
    expect(recuperados, unorderedEquals(['Marlboro', 'Sueltos']));
    expect((await producto(db, marlboro)).tipoCigarrillo, 'atado');
    expect((await producto(db, marlboro)).actualizadoEn, isNotNull, reason: 'así viaja al otro equipo');
    expect((await producto(db, sueltos)).tipoCigarrillo, 'suelto', reason: 'la última venta marcada');
    expect((await producto(db, coca)).tipoCigarrillo, 'ninguno');
    expect((await producto(db, camel)).tipoCigarrillo, 'atado', reason: 'ya marcado: no se toca');
    expect(await recuperarMarcaDeCigarrillos(db), isEmpty, reason: 'correrlo de nuevo no cambia nada');
  });

  test('una base v57 real sube a v58 y recupera la marca sola', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v58_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    final usuario = await nueva.into(nueva.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesion = await abrirSesion(nueva, usuarioId: usuario, fondoInicialCentavos: 0);
    final marlboro = await nueva.into(nueva.productos).insert(ProductosCompanion.insert(nombre: 'Marlboro'));
    await vender(nueva, sesion, usuario, marlboro, 'atado', DateTime(2026, 10, 1));
    await nueva.close();

    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('PRAGMA user_version = 57');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(() => db.close());
    expect((await producto(db, marlboro)).tipoCigarrillo, 'atado');
  });
}
