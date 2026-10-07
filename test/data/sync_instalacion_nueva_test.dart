// Una PC instalada de cero (revisión 2026-10-03): el usuario inicial, "Varios" y las categorías de la plantilla nacían
// sin `global_id` y nunca salían por la sync, así que el otro equipo rechazaba las sesiones y ventas atadas a ellos.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_plantillas.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_usuarios.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('lo que siembra una PC nueva sale por la sync, y la sesión viaja con su usuario', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    addTearDown(pc.close);
    final usuario = (await listarUsuarios(pc)).single;
    await renombrarUsuario(pc, usuario.id, 'Ana');
    await aplicarPlantillaRubro(pc, PlantillaRubro.almacen);
    await abrirSesion(pc, usuarioId: usuario.id, fondoInicialCentavos: 0);

    final usuarios = await cambiosDesde(pc, tabla: 'usuarios', desde: 0);
    expect(usuarios.map((f) => f['global_id']), [globalIdUsuarioInicial]);
    final productos = await cambiosDesde(pc, tabla: 'productos', desde: 0);
    expect(productos.map((f) => f['global_id']), contains(globalIdProductoVarios));
    final categorias = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    expect(categorias, hasLength((await pc.select(pc.categorias).get()).length));
    expect(categorias, isNotEmpty);
    final sesiones = await cambiosDesde(pc, tabla: 'sesiones_de_caja', desde: 0);
    expect(sesiones.single['usuario_abrio_id_gid'], globalIdUsuarioInicial);
  });

  test('otro equipo aplica todo sin rechazos y converge en un solo usuario inicial y un solo "Varios"', () async {
    final pc = AppDatabase(NativeDatabase.memory());
    final otro = AppDatabase(NativeDatabase.memory());
    addTearDown(pc.close);
    addTearDown(otro.close);
    final usuario = (await listarUsuarios(pc)).single;
    await renombrarUsuario(pc, usuario.id, 'Ana');
    await aplicarPlantillaRubro(pc, PlantillaRubro.almacen);
    await abrirSesion(pc, usuarioId: usuario.id, fondoInicialCentavos: 0);

    for (final tabla in tablasSincronizables.keys) {
      final filas = await cambiosDesde(pc, tabla: tabla, desde: 0);
      final rechazadas = await aplicarCambios(otro, tabla: tabla, filas: filas);
      expect(rechazadas, isEmpty, reason: 'en $tabla no tiene que quedar nada sin aplicar');
    }

    final usuariosOtro = await listarUsuarios(otro);
    expect(usuariosOtro.map((u) => u.nombre), ['Ana'], reason: 'el usuario sembrado es el mismo en los dos equipos');
    final varios = await (otro.select(otro.productos)..where((p) => p.esVarios.equals(true))).get();
    expect(varios, hasLength(1));
    final sesion = (await otro.select(otro.sesionesDeCaja).get()).single;
    expect(sesion.usuarioAbrioId, usuariosOtro.single.id);
  });

  test('una base v48 instalada de cero sube a v49 con la identidad completa', () async {
    final carpeta = await Directory.systemTemp.createTemp('la_plazoleta_migracion_v49_');
    addTearDown(() => carpeta.delete(recursive: true));
    final archivo = File('${carpeta.path}/base.sqlite');
    final nueva = AppDatabase(NativeDatabase(archivo));
    await aplicarPlantillaRubro(nueva, PlantillaRubro.kiosco);
    await nueva.close();

    // Como quedaba una PC nueva antes del arreglo: las tres cosas sin identidad, y una promo sin artículos.
    final crudo = sqlite3.sqlite3.open(archivo.path);
    try {
      crudo.execute('UPDATE usuarios SET global_id = NULL');
      crudo.execute('UPDATE productos SET global_id = NULL');
      crudo.execute('UPDATE categorias SET global_id = NULL');
      crudo.execute("INSERT INTO productos (nombre, es_promo) VALUES ('Promo merienda', 1)");
      crudo.execute('PRAGMA user_version = 48');
    } finally {
      crudo.close();
    }

    final db = AppDatabase(NativeDatabase(archivo));
    addTearDown(db.close);
    expect((await listarUsuarios(db)).single.globalId, globalIdUsuarioInicial);
    final productos = await db.select(db.productos).get();
    expect(productos.firstWhere((p) => p.esVarios).globalId, globalIdProductoVarios);
    // Hasta la v61 las promos quedaban sin identidad (sus artículos no viajaban); desde la v62 viajan con ellos (2026-10-07).
    final promo = productos.firstWhere((p) => p.esPromo);
    expect(promo.globalId, isNotNull);
    expect(promo.componentesPromo, '[]');
    final categorias = await db.select(db.categorias).get();
    expect(categorias, isNotEmpty);
    expect(categorias.every((c) => c.globalId != null), isTrue);
  });
}
